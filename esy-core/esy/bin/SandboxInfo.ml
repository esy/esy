open Esy

type t = {
  sandbox : Sandbox.t;
  task : Task.t;
  commandEnv : Environment.t;
  sandboxEnv : Environment.t;
}

let cachePath (cfg : Config.t) =
  let hash = [
    Path.to_string cfg.storePath;
    Path.to_string cfg.localStorePath;
    Path.to_string cfg.sandboxPath;
    cfg.esyVersion
  ]
    |> String.concat "$$"
    |> Digest.string
    |> Digest.to_hex
  in
  let name = Printf.sprintf "sandbox-%s" hash in
  Path.(cfg.sandboxPath / "node_modules" / ".cache" / "_esy" / name)

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
      let%bind () = Fs.createDirectory (Path.parent cachePath) in
      Lwt_io.with_file ~mode:Lwt_io.Output (Path.to_string cachePath) f
    in

    let%bind () =
      let f oc =
        let%bind commandEnv = RunAsync.liftOfRun(
            let header =
              let pkg = info.sandbox.root in
              Printf.sprintf "# Command environment for %s@%s" pkg.name pkg.version
            in
            info.commandEnv
            |> Environment.renderToShellSource ~header cfg
          ) in
        let%lwt () = Lwt_io.write oc commandEnv in
        let%lwt () = Lwt_io.flush oc in
        return ()
      in
      let commandEnvPath = Path.(
          cfg.sandboxPath
          / "node_modules"
          / ".cache"
          / "_esy"
          / "build"
          / "bin"
          / "command-env"
        ) in
      let%bind () = Fs.createDirectory (Path.parent commandEnvPath) in
      Lwt_io.with_file ~mode:Lwt_io.Output (Path.to_string commandEnvPath) f
    in

    return ()

  in Esy.Perf.measureTime ~label:"writing sandbox info cache" f

let readCache (cfg : Config.t) =
  let open RunAsync.Syntax in
  let f () =
    let cachePath = cachePath cfg in
    let f ic =
      let%lwt info = (Lwt_io.read_value ic : t Lwt.t) in
      let%bind isStale =
        let checkMtime (path, mtime) =
          let%bind { Unix.st_mtime = curMtime; _ } = Fs.stat path in
          return (curMtime > mtime)
        in
        info.sandbox.manifestInfo
        |> List.map checkMtime
        |> RunAsync.joinAll
      in
      if List.exists (fun x -> x) isStale
      then return None
      else return (Some info)
    in
    try%lwt Lwt_io.with_file ~mode:Lwt_io.Input (Path.to_string cachePath) f
    with | Unix.Unix_error _ -> return None
  in Esy.Perf.measureTime ~label:"reading sandbox info cache" f

let ofConfig (cfg : Config.t) =
  let open RunAsync.Syntax in
  let makeInfo () =
    let f () =
      let%bind sandbox = Sandbox.ofDir cfg in
      let%bind task, commandEnv, sandboxEnv = RunAsync.liftOfRun (
          let open Run.Syntax in
          let%bind task = Task.ofPackage sandbox.root in
          let%bind commandEnv = Task.commandEnv sandbox.root in
          let%bind sandboxEnv = Task.sandboxEnv sandbox.root in
          return (task, commandEnv, sandboxEnv)
        ) in
      return {task; sandbox; commandEnv; sandboxEnv}
    in Esy.Perf.measureTime ~label:"constructing sandbox info" f
  in
  match%bind readCache cfg with
  | Some info -> return info
  | None ->
    let%bind info = makeInfo () in
    let%bind () = writeCache cfg info in
    return info
