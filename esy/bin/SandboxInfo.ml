open Esy

type t = {
  sandbox : Sandbox.t;
  task : Task.t;
  commandEnv : Environment.Bindings.t;
  sandboxEnv : Environment.Bindings.t;
}

let cachePath (cfg : Config.t) =
  let hash = [
    Path.toString cfg.buildConfig.storePath;
    Path.toString cfg.buildConfig.localStorePath;
    Path.toString cfg.buildConfig.sandboxPath;
    cfg.esyVersion
  ]
    |> String.concat "$$"
    |> Digest.string
    |> Digest.to_hex
  in
  let name = Printf.sprintf "sandbox-%s" hash in
  Path.(cfg.buildConfig.sandboxPath / "node_modules" / ".cache" / "_esy" / name)

let writeCache (cfg : Config.t) (info : t) =
  let open RunAsync.Syntax in
  let f () =

    let%bind () =
      let f oc =
        let%lwt () = Lwt_io.write_value oc info in
        let%lwt () = Lwt_io.flush oc in
        return ()
      in
      let cachePath = cachePath cfg in
      let%bind () = Fs.createDir (Path.parent cachePath) in
      Lwt_io.with_file ~mode:Lwt_io.Output (Path.toString cachePath) f
    in

    let%bind () =
      let writeData filename data =
        let f oc =
          let%lwt () = Lwt_io.write oc data in
          let%lwt () = Lwt_io.flush oc in
          return ()
        in
        Lwt_io.with_file ~mode:Lwt_io.Output (Path.toString filename) f
      in
      let sandboxBin = Path.(
          cfg.buildConfig.sandboxPath
          / "node_modules"
          / ".cache"
          / "_esy"
          / "build"
          / "bin"
      ) in
      let%bind () = Fs.createDir sandboxBin in

      let%bind commandEnv = RunAsync.ofRun (
        let header =
          let pkg = info.sandbox.root in
          Printf.sprintf "# Command environment for %s@%s" pkg.name pkg.version
        in
        Environment.renderToShellSource ~header info.commandEnv
      ) in
      let%bind () =
        let filename = Path.(sandboxBin / "command-env") in
        writeData filename commandEnv in
      let%bind () =
        let filename = Path.(sandboxBin / "command-exec") in
        let commandExec = "#!/bin/bash\n" ^ commandEnv ^ "\nexec \"$@\"" in
        let%bind () = writeData filename commandExec in
        let%bind () = Fs.chmod 0o755 filename in
        return ()
      in return ()

    in

    return ()

  in Perf.measureLwt ~label:"writing sandbox info cache" f

let readCache (cfg : Config.t) =
  let open RunAsync.Syntax in
  let f () =
    let cachePath = cachePath cfg in
    let f ic =
      let%lwt info = (Lwt_io.read_value ic : t Lwt.t) in
      let%bind isStale =
        let%bind checks =
          RunAsync.List.joinAll (
            let f (path, mtime) =
              match%lwt Fs.stat path with
              | Ok { Unix.st_mtime = curMtime; _ } -> return (curMtime > mtime)
              | Error _ -> return true
            in
            List.map ~f info.sandbox.manifestInfo
          )
        in
        return (List.exists ~f:(fun x -> x) checks)
      in
      if isStale
      then return None
      else return (Some info)
    in
    try%lwt Lwt_io.with_file ~mode:Lwt_io.Input (Path.toString cachePath) f
    with | Unix.Unix_error _ -> return None
  in Perf.measureLwt ~label:"reading sandbox info cache" f

let ofConfig (cfg : Config.t) =
  let open RunAsync.Syntax in
  let makeInfo () =
    let f () =
      let%bind sandbox = Sandbox.ofDir cfg in
      let%bind task, commandEnv, sandboxEnv = RunAsync.ofRun (
        let open Run.Syntax in
        let%bind task = Task.ofPackage sandbox.root in
        let%bind commandEnv =
          let%bind env = Task.commandEnv task in
          return (Config.Environment.Bindings.render cfg.buildConfig env)
        in
        let%bind sandboxEnv =
          let%bind env = Task.sandboxEnv task in
          return (Config.Environment.Bindings.render cfg.buildConfig env)
        in
        return (task, commandEnv, sandboxEnv)
      ) in
      return {task; sandbox; commandEnv; sandboxEnv}
    in Perf.measureLwt ~label:"constructing sandbox info" f
  in
  match%bind readCache cfg with
  | Some info -> return info
  | None ->
    let%bind info = makeInfo () in
    let%bind () = writeCache cfg info in
    return info

let findTaskByName ~pkgName root =
  let f (task : Task.t) =
    let pkg = Task.pkg task in
    pkg.name = pkgName
  in
  Task.Graph.find ~f root

let resolvePackage ~pkgName ~cfg info =
  let open RunAsync.Syntax in
  match findTaskByName ~pkgName info.task
  with
  | None -> errorf "package %s isn't built yet, run 'esy build'" pkgName
  | Some task ->
    let installPath = Config.Path.toPath cfg.Config.buildConfig (Task.installPath task) in
    let%bind built = Fs.exists installPath in
    if built
    then return installPath
    else errorf "package %s isn't built yet, run 'esy build'" pkgName

let ocamlfind = resolvePackage ~pkgName:"@opam/ocamlfind"
let ocaml = resolvePackage ~pkgName:"ocaml"

let splitBy line ch =
  match String.index line ch with
  | idx ->
    let key = String.sub line 0 idx in
    let pos = idx + 1 in
    let val_ = String.(trim (sub line pos (length line - pos))) in
    Some (key, val_)
  | exception Not_found -> None

let libraries ~cfg ~ocamlfind ?builtIns ?task () =
  let open RunAsync.Syntax in
  let ocamlpath =
    match task with
    | Some task ->
      Config.Path.(Task.installPath task / "lib" |> toPath cfg.Config.buildConfig)
      |> Path.toString
    | None -> ""
  in
  let env =
    `CustomEnv Astring.String.Map.(
      empty |>
      add "OCAMLPATH" ocamlpath
  ) in
  let cmd = Cmd.(v (p ocamlfind) % "list") in
  let%bind out = ChildProcess.runOut ~env cmd in
  let libs =
    String.split_on_char '\n' out |>
    List.map ~f:(fun line -> splitBy line ' ')
    |> List.filterNone
    |> List.map ~f:(fun (key, _) -> key)
    |> List.rev
  in
  match builtIns with
  | Some discard ->
    return (List.diff libs discard)
  | None -> return libs

let modules ~ocamlobjinfo archive =
  let open RunAsync.Syntax in
  let env = `CustomEnv Astring.String.Map.empty in
  let cmd = let open Cmd in (v (p ocamlobjinfo)) % archive in
  let%bind out = ChildProcess.runOut ~env cmd in
  let startsWith s1 s2 =
    let len1 = String.length s1 in
    let len2 = String.length s2 in
    match len1 < len2 with
    | true -> false
    | false -> (String.sub s1 0 len2) = s2
  in
  let lines =
    let f line =
      startsWith line "Name: " || startsWith line "Unit name: "
    in
    String.split_on_char '\n' out
    |> List.filter ~f
    |> List.map ~f:(fun line -> splitBy line ':')
    |> List.filterNone
    |> List.map ~f:(fun (_, val_) -> val_)
    |> List.rev
  in
  return lines

module Findlib = struct
  type meta = {
    package : string;
    description : string;
    version : string;
    archive : string;
    location : string;
  }

  let query ~cfg ~ocamlfind ~task lib =
    let open RunAsync.Syntax in
    let ocamlpath =
      Config.Path.(Task.installPath task / "lib" |> toPath cfg.Config.buildConfig)
    in
    let env =
      `CustomEnv Astring.String.Map.(
        empty |>
        add "OCAMLPATH" (Path.toString ocamlpath)
    ) in
    let cmd = Cmd.(
      v (p ocamlfind)
      % "query"
      % "-predicates"
      % "byte,native"
      % "-long-format"
      % lib
    ) in
    let%bind out = ChildProcess.runOut ~env cmd in
    let lines =
      String.split_on_char '\n' out
      |> List.map ~f:(fun line -> splitBy line ':')
      |> List.filterNone
      |> List.rev
    in
    let findField ~name  =
      let f (field, value) =
        match field = name with
        | true -> Some value
        | false -> None
      in
      lines
      |> List.map ~f
      |> List.filterNone
      |> List.hd
    in
    return {
      package = findField ~name:"package";
      description = findField ~name:"description";
      version = findField ~name:"version";
      archive = findField ~name:"archive(s)";
      location = findField ~name:"location";
    }
end
