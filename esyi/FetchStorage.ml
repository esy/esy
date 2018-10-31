module String = Astring.String

module D = Dist

module Dist = struct
  type t = {
    sandbox : Sandbox.t;
    source : Source.t;
    archive : DistStorage.archive option;
    pkg : Solution.Package.t;
  }

  let id dist = Solution.Package.id dist.pkg
  let pkg dist = dist.pkg
  let source dist = dist.source

  let sourceStagePath dist =
    match dist.source with
    | Source.Link link ->
      Path.(dist.sandbox.spec.path // link.path |> normalize)
    | _ ->
      let name = Path.safeSeg dist.pkg.name in
      let id =
        Source.show dist.source
        |> Digest.string
        |> Digest.to_hex
        |> Path.safeSeg
      in
      Path.(dist.sandbox.cfg.sourceStagePath / (name ^ "-" ^ id))

  let sourceInstallPath dist =
    match dist.source with
    | Source.Link link ->
      Path.(dist.sandbox.spec.path // link.path |> normalize)
    | _ ->
      let name = Path.safeSeg dist.pkg.name in
      let id =
        Source.show dist.source
        |> Digest.string
        |> Digest.to_hex
        |> Path.safeSeg
      in
      Path.(dist.sandbox.cfg.sourceInstallPath / (name ^ "-" ^ id))

  let pp fmt dist =
    Fmt.pf fmt "%s@%a" dist.pkg.name Version.pp dist.pkg.version
end

module PackageJson : sig
  type t

  type lifecycle = {
    postinstall : string option;
    install : string option;
  }

  val ofDir : Path.t -> t option RunAsync.t

  val bin : sourcePath:Path.t -> t -> (string * Path.t) list
  val lifecycle : t -> lifecycle option

end = struct

  module Lifecycle = struct
    type t = {
      postinstall : (string option [@default None]);
      install : (string option [@default None]);
    }
    [@@deriving of_yojson { strict = false }]
  end

  module Bin = struct
    type t =
      | Empty
      | One of string
      | Many of string StringMap.t

    let of_yojson =
      let open Result.Syntax in
      function
      | `String cmd ->
        let cmd = String.trim cmd in
        begin match cmd with
        | "" -> return Empty
        | cmd -> return (One cmd)
        end
      | `Assoc items ->
        let%bind items =
          let f cmds (name, json) =
            match json with
            | `String cmd -> return (StringMap.add name cmd cmds)
            | _ -> error "expected a string"
          in
          Result.List.foldLeft ~f ~init:StringMap.empty items
        in
        return (Many items)
      | _ -> error "expected a string or an object"
  end

  type t = {
    name : string option [@default None];
    bin : (Bin.t [@default Bin.Empty]);
    scripts : (Lifecycle.t option [@default None]);
    esy : (Json.t option [@default None]);
  } [@@deriving of_yojson { strict = false }]

  type lifecycle = Lifecycle.t = {
    postinstall : string option;
    install : string option;
  }

  let ofDir path =
    let open RunAsync.Syntax in
    let filename = Path.(path / "package.json") in
    if%bind Fs.exists filename
    then
      let%bind json = Fs.readJsonFile filename in
      let%bind manifest = RunAsync.ofRun (Json.parseJsonWith of_yojson json) in
      return (Some manifest)
    else
      return None

  let bin ~sourcePath pkgJson =
    let makePathToCmd cmdPath = Path.(sourcePath // v cmdPath |> normalize) in
    match pkgJson.bin, pkgJson.name with
    | Bin.One cmd, Some name ->
      [name, makePathToCmd cmd]
    | Bin.One cmd, None ->
      let cmd = makePathToCmd cmd in
      let name = Path.basename cmd in
      [name, cmd]
    | Bin.Many cmds, _ ->
      let f name cmd cmds = (name, makePathToCmd cmd)::cmds in
      (StringMap.fold f cmds [])
    | Bin.Empty, _ -> []

  let lifecycle pkgJson = pkgJson.scripts

end

let fetch ~sandbox (pkg : Solution.Package.t) =
  let open RunAsync.Syntax in

  let rec fetch' errs sources =
    match sources with
    | (Source.Link _ as source)::_rest ->
      return {Dist. sandbox; pkg; source; archive = None;}
    | (Source.Dist dist as source)::rest ->
      begin match%bind DistStorage.fetch ~cfg:sandbox.Sandbox.cfg dist with
      | Ok archive ->
        return {Dist. sandbox; pkg; source; archive = Some archive;}
      | Error err -> fetch' ((source, err)::errs) rest
      end
    | [] ->
      Logs_lwt.err (fun m ->
        let ppErr fmt (source, err) =
          Fmt.pf fmt
            "source: %a@\nerror: %a"
            Source.pp source
            Run.ppError err
        in
        m "unable to fetch %a:@[<v 2>@\n%a@]"
          Solution.Package.pp pkg
          Fmt.(list ~sep:(unit "@\n") ppErr) errs
      );%lwt
      error "installation error"
  in

  match pkg.source with
  | Package.Link {path; manifest;} ->
    return {
      Dist.
      sandbox;
      pkg;
      source = Source.Link {path;manifest;};
      archive = None;
    }
  | Package.Install {source = main, mirrors; _} ->
    fetch' [] (main::mirrors)

let unpack ~path dist =
  let open RunAsync.Syntax in

  let%bind () =
    match dist.Dist.archive with
    | None ->
      return ()
    | Some archive ->
      let%bind () = Fs.rmPath path in
      let%bind () = Fs.createDir path in
      DistStorage.unpack
        ~cfg:dist.sandbox.Sandbox.cfg
        ~dst:path
        archive
  in

  return ()

let layoutFiles files path =
  RunAsync.List.mapAndWait
    ~f:(File.placeAt path)
    files

let runLifecycleScript ?env ~lifecycleName pkg sourcePath script =
  let%lwt () = Logs_lwt.app
    (fun m ->
      m "%a: running %a lifecycle"
      Solution.Package.pp pkg
      Fmt.(styled `Bold string) lifecycleName
    )
  in

  let readAndCloseChan ic =
    Lwt.finalize
      (fun () -> Lwt_io.read ic)
      (fun () -> Lwt_io.close ic)
  in

  let f p =
    let%lwt stdout = readAndCloseChan p#stdout
    and stderr = readAndCloseChan p#stderr in
    match%lwt p#status with
    | Unix.WEXITED 0 ->
      RunAsync.return ()
    | _ ->
      Logs_lwt.err (fun m -> m
        "@[<v>command failed: %s@\nstderr:@[<v 2>@\n%s@]@\nstdout:@[<v 2>@\n%s@]@]"
        script stderr stdout
      );%lwt
      RunAsync.error "error running command"
  in

  try%lwt
    (* We don't need to wrap the install path on Windows in quotes *)
    let installationPath =
      match System.Platform.host with
      | Windows -> Path.show sourcePath
      | _ -> Filename.quote (Path.show sourcePath)
    in
    let script =
      Printf.sprintf
        "cd %s && %s"
        installationPath
        script
    in
    let cmd =
      match System.Platform.host with
      | Windows -> ("", [|"cmd.exe";("/c " ^ script)|])
      | _ -> ("/bin/bash", [|"/bin/bash";"-c";script|])
    in
    let env =
      let open Option.Syntax in
      let%bind env = env in
      let%bind _, env = ChildProcess.prepareEnv env in
      return env
    in
    Lwt_process.with_process_full ?env cmd f
  with
  | Unix.Unix_error (err, _, _) ->
    let msg = Unix.error_message err in
    RunAsync.error msg
  | _ ->
    RunAsync.error "error running subprocess"

let runLifecycle ~prepareLifecycleEnv pkg sourcePath lifecycle =
  let open RunAsync.Syntax in
  let%bind env =
    let%bind override = prepareLifecycleEnv sourcePath Astring.String.Map.empty in
    return (ChildProcess.CurrentEnvOverride override)
  in

  let%bind () =
    match lifecycle.PackageJson.install with
    | Some cmd -> runLifecycleScript ~env ~lifecycleName:"install" pkg sourcePath cmd
    | None -> return ()
  in

  let%bind () =
    match lifecycle.PackageJson.postinstall with
    | Some cmd -> runLifecycleScript ~env ~lifecycleName:"postinstall" pkg sourcePath cmd
    | None -> return ()
  in

  return ()

let installBinWrapper ~binPath (name, origPath) =
  let open RunAsync.Syntax in
  Logs_lwt.debug (fun m ->
    m "Fetch:installBinWrapper: %a / %s -> %a"
    Path.pp origPath name Path.pp binPath
  );%lwt
  if%bind Fs.exists origPath
  then (
    let%bind () = Fs.chmod 0o777 origPath in
    let destPath = Path.(binPath / name) in
    if%bind Fs.exists destPath
    then return ()
    else Fs.symlink ~src:origPath destPath
  ) else (
    Logs_lwt.warn (fun m -> m "missing %a defined as binary" Path.pp origPath);%lwt
    return ()
  )

let install ~prepareLifecycleEnv dist =
  (** TODO: need to sync here so no two same tasks are running at the same time *)
  let open RunAsync.Syntax in
  RunAsync.contextf (

    let%bind binPath =
      let binPath = SandboxSpec.binPath dist.sandbox.Sandbox.spec in
      let%bind () = Fs.createDir binPath in
      return binPath
    in

    let%bind sourcePath, pkgJson =
      match dist.Dist.pkg.source with
      | Package.Link {path; _} ->
        let%bind pkgJson = PackageJson.ofDir path in
        let sourcePath = Path.(dist.sandbox.Sandbox.spec.path // path) in
        return (sourcePath, pkgJson)
      | Package.Install _ ->
        let sourceInstallPath = Dist.sourceInstallPath dist in
        if%bind Fs.exists sourceInstallPath
        then
          let%bind pkgJson = PackageJson.ofDir sourceInstallPath in
          return (sourceInstallPath, pkgJson)
        else (
          let sourceStagePath = Dist.sourceStagePath dist in
          let%bind () = unpack ~path:sourceStagePath dist in
          let%bind () =
            let%bind filesOfOpam =
              Solution.Package.readOpamFiles 
                dist.pkg
            in
            let%bind filesOfOverride =
              Package.Overrides.files
                ~cfg:dist.sandbox.cfg
                dist.pkg.overrides
            in
            layoutFiles (filesOfOpam @ filesOfOverride) sourceStagePath
          in
          let%bind pkgJson = PackageJson.ofDir sourceStagePath in
          let lifecycle = Option.bind ~f:PackageJson.lifecycle pkgJson in
          let%bind () =
            match lifecycle with
            | Some lifecycle ->
              let%bind () =
                runLifecycle
                  ~prepareLifecycleEnv
                  dist.pkg
                  sourceStagePath
                  lifecycle
              in
              RewritePrefix.rewritePrefix
                ~origPrefix:sourceStagePath
                ~destPrefix:sourceStagePath
                sourceStagePath
            | None -> return ()
          in
          let%bind () = Fs.rename ~src:sourceStagePath sourceInstallPath in
          return (sourceInstallPath, pkgJson)
        )
    in

    (* link bin wrappers *)
    let%bind () =
      match pkgJson with
      | Some pkgJson ->
        let bin = PackageJson.bin ~sourcePath pkgJson in
        RunAsync.List.mapAndWait ~f:(installBinWrapper ~binPath) bin
      | None -> return ()
    in

    return ()
  ) "installing %a" Dist.pp dist
