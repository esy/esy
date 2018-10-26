open Esy

module SandboxSpec = EsyInstall.SandboxSpec
module Solution = EsyInstall.Solution
module Lockfile = EsyInstall.LockfileV1
module Version = EsyInstall.Version
module PackageId = EsyInstall.PackageId

let runAsyncToCmdlinerRet res =
  match Lwt_main.run res with
  | Ok v -> `Ok v
  | Error error ->
    Lwt_main.run (Cli.ProgressReporter.clearStatus ());
    Format.fprintf Format.err_formatter "@[%a@]@." Run.ppError error;
    `Error (false, "exiting due to errors above")

(**
 * This module encapsulates info about esy runtime - its version, current
 * working directory and so on.
 *
 * XXX: Probably needs to be merged with Config
 *)
module EsyRuntime = struct

  let currentWorkingDir = Path.v (Sys.getcwd ())
  let currentExecutable = Path.v Sys.executable_name

  let resolve req =
    let open RunAsync.Syntax in
    let%bind currentFilename = Fs.realpath currentExecutable in
    let currentDirname = Path.parent currentFilename in
    let%bind cmd =
      match NodeResolution.resolve req currentDirname with
      | Ok (Some path) -> return path
      | Ok (None) ->
        let msg =
          Printf.sprintf
          "unable to resolve %s from %s"
          req
          (Path.show currentDirname)
        in
        RunAsync.error msg
      | Error (`Msg err) -> RunAsync.error err
    in return cmd

  let resolveCmd req =
    let open RunAsync.Syntax in
    let%bind path = resolve req in
    return (Cmd.v (Path.show path))

  let esyInstallRelease =
    RunAsync.runExn (resolve "../../../../bin/esyInstallRelease.js")

  let esyBuildPackageCmd =
    RunAsync.runExn (resolveCmd "../../esy-build-package/bin/esyBuildPackageCommand.exe")

  let fastreplacestringCmd =
    RunAsync.runExn (resolveCmd "../../esy-build-package/bin/fastreplacestring.exe")

  module EsyPackageJson = struct
    type t = {
      version : string
    } [@@deriving of_yojson { strict = false }]

    let read () =
      let pkgJson =
        let open RunAsync.Syntax in
        let%bind filename = resolve "../../../../package.json" in
        let%bind data = Fs.readFile filename in
        Lwt.return (Json.parseStringWith of_yojson data)
      in Lwt_main.run pkgJson
  end

  let version =
    match EsyPackageJson.read () with
    | Ok pkgJson -> pkgJson.EsyPackageJson.version
    | Error err ->
      let msg =
        let err = Run.formatError err in
        Printf.sprintf "invalid esy installation: cannot read package.json %s" err in
      failwith msg

  let concurrency =
    (** TODO: handle more platforms, right now this is tested only on macOS and Linux *)
    let cmd = Bos.Cmd.(v "getconf" % "_NPROCESSORS_ONLN") in
    match Bos.OS.Cmd.(run_out cmd |> to_string) with
    | Ok out ->
      begin match out |> String.trim |> int_of_string_opt with
      | Some n -> n
      | None -> 1
      end
    | Error _ -> 1
end

let findSandboxPathStartingWith currentPath =
  let open RunAsync.Syntax in
  let isSandbox path =
    let%bind items = Fs.listDir path in
    let f name =
      match name with
      | "package.json"
      | "esy.json"
      | "opam" -> true
      | name -> Path.(v name |> hasExt ".opam")
    in
    return (List.exists ~f items)
  in
  let rec climb path =
    if%bind isSandbox path
    then return path
    else
      let parent = Path.parent path in
      if not (Path.compare path parent = 0)
      then climb (Path.parent path)
      else errorf "No sandbox found (from %a and up)" Path.ppPretty currentPath
  in
  climb currentPath

module CommonOptions = struct
  open Cmdliner

  type t = {
    cfg : Config.t;
    spec : EsyInstall.SandboxSpec.t;
    installSandbox : EsyInstall.Sandbox.t;
  }

  let docs = Manpage.s_common_options

  let prefixPath =
    let doc = "Specifies esy prefix path." in
    let env = Arg.env_var "ESY__PREFIX" ~doc in
    Arg.(
      value
      & opt (some Cli.pathConv) None
      & info ["prefix-path"] ~env ~docs ~doc
    )

  let opamRepositoryArg =
    let doc = "Specifies an opam repository to use." in
    let docv = "REMOTE[:LOCAL]" in
    let env = Arg.env_var "ESYI__OPAM_REPOSITORY" ~doc in
    Arg.(
      value
      & opt (some Cli.checkoutConv) None
      & (info ["opam-repository"] ~env ~doc ~docv)
    )

  let esyOpamOverrideArg =
    let doc = "Specifies an opam override repository to use." in
    let docv = "REMOTE[:LOCAL]" in
    let env = Arg.env_var "ESYI__OPAM_OVERRIDE"  ~doc in
    Arg.(
      value
      & opt (some Cli.checkoutConv) None
      & info ["opam-override-repository"] ~env ~doc ~docv
    )

  let cacheTarballsPath =
    let doc = "Specifies tarballs cache directory." in
    Arg.(
      value
      & opt (some Cli.pathConv) None
      & info ["cache-tarballs-path"] ~doc
    )

  let npmRegistryArg =
    let doc = "Specifies npm registry to use." in
    let env = Arg.env_var "NPM_CONFIG_REGISTRY" ~doc in
    Arg.(
      value
      & opt (some string) None
      & info ["npm-registry"] ~env ~doc
    )

  let solveTimeoutArg =
    let doc = "Specifies timeout for running depsolver." in
    Arg.(
      value
      & opt (some float) None
      & info ["solve-timeout"] ~doc
    )

  let skipRepositoryUpdateArg =
    let doc = "Skip updating opam-repository and esy-opam-overrides repositories." in
    Arg.(
      value
      & flag
      & info ["skip-repository-update"] ~doc
    )

  let cachePathArg =
    let doc = "Specifies cache directory.." in
    let env = Arg.env_var "ESYI__CACHE" ~doc in
    Arg.(
      value
      & opt (some Cli.pathConv) None
      & info ["cache-path"] ~env ~doc
    )

  let term sandboxPath =

    let sandboxPath =
      match sandboxPath with
      | Some sandboxPath ->
        RunAsync.return (
          if Path.isAbs sandboxPath
          then sandboxPath
          else Path.(EsyRuntime.currentWorkingDir // sandboxPath)
        )
      | None ->
        findSandboxPathStartingWith (Path.currentPath ())
    in

    let parse
      prefixPath
      cachePath
      cacheTarballsPath
      opamRepository
      esyOpamOverride
      npmRegistry
      solveTimeout
      skipRepositoryUpdate
      =
      let copts =
        let open RunAsync.Syntax in

        let%bind sandboxPath = sandboxPath in
        let%bind spec = EsyInstall.SandboxSpec.ofPath sandboxPath in

        let%bind prefixPath = match prefixPath with
          | Some prefixPath -> return (Some prefixPath)
          | None ->
            let%bind rc = EsyRc.ofPath spec.EsyInstall.SandboxSpec.path in
            return rc.EsyRc.prefixPath
        in

        let%bind installCfg =
          let%bind esySolveCmd =
            let%bind cmd = EsyRuntime.resolve "esy-solve-cudf/esySolveCudfCommand.exe" in
            return Cmd.(v (p cmd))
          in
          EsyInstall.Config.make
            ~fastreplacestringCmd:EsyRuntime.fastreplacestringCmd
            ~esySolveCmd
            ~skipRepositoryUpdate
            ?cachePath
            ?cacheTarballsPath
            ?npmRegistry
            ?opamRepository
            ?esyOpamOverride
            ?solveTimeout
            ()
        in

        let%bind cfg =
          RunAsync.ofRun (
            Config.make
              ~installCfg
              ~spec
              ~esyVersion:EsyRuntime.version
              ~fastreplacestringCmd:EsyRuntime.fastreplacestringCmd
              ~esyBuildPackageCmd:EsyRuntime.esyBuildPackageCmd
              ~prefixPath
              ()
          )
        in

        let%bind installSandbox =
          EsyInstall.Sandbox.make ~cfg:installCfg spec
        in

        return {cfg; installSandbox; spec;}
      in
      runAsyncToCmdlinerRet copts
    in
    Term.(ret (
      const parse
      $ prefixPath
      $ cachePathArg
      $ cacheTarballsPath
      $ opamRepositoryArg
      $ esyOpamOverrideArg
      $ npmRegistryArg
      $ solveTimeoutArg
      $ skipRepositoryUpdateArg
    ))

end

module SandboxInfo = struct

  type t = {
    filesUsed : FileInfo.t list;
    spec: EsyInstall.SandboxSpec.t;
    solution : Solution.t option;
    installation : EsyInstall.Installation.t option;
    plan : Plan.t option;
    scripts : Scripts.t;
  }

  let plan info =
    match info.plan with
    | Some plan -> RunAsync.return plan
    | None -> RunAsync.errorf "no installation found, run 'esy install'"

  let solution info =
    match info.solution with
    | Some solution -> RunAsync.return solution
    | None -> RunAsync.errorf "no installation found, run 'esy install'"

  let installation info =
    match info.installation with
    | Some installation -> RunAsync.return installation
    | None -> RunAsync.errorf "no installation found, run 'esy install'"

  let cachePath (cfg : Config.t) (spec : EsyInstall.SandboxSpec.t) =
    let hash = [
      Path.show cfg.buildCfg.storePath;
      Path.show spec.path;
      cfg.esyVersion
    ]
      |> String.concat "$$"
      |> Digest.string
      |> Digest.to_hex
    in
    Path.(EsyInstall.SandboxSpec.cachePath spec / ("sandbox-" ^ hash))

  let writeCache (copts : CommonOptions.t) (info : t) =
    let open RunAsync.Syntax in
    let f () =

      let%bind () =
        let f oc =
          let%lwt () = Lwt_io.write_value oc info in
          let%lwt () = Lwt_io.flush oc in
          return ()
        in
        let cachePath = cachePath copts.cfg info.spec in
        let%bind () = Fs.createDir (Path.parent cachePath) in
        Lwt_io.with_file ~mode:Lwt_io.Output (Path.show cachePath) f
      in

      let%bind () =
        if EsyInstall.SandboxSpec.isDefault info.spec
        then
          let writeData filename data =
            let f oc =
              let%lwt () = Lwt_io.write oc data in
              let%lwt () = Lwt_io.flush oc in
              return ()
            in
            Lwt_io.with_file ~mode:Lwt_io.Output (Path.show filename) f
          in
          let sandboxBin = SandboxSpec.binPath info.spec in
          let%bind () = Fs.createDir sandboxBin in
          match info.plan with
          | None -> return ()
          | Some plan ->
            begin match Plan.rootTask plan with
            | None -> return ()
            | Some task ->
              let%bind commandEnv = RunAsync.ofRun (
                let open Run.Syntax in
                let header = "# Command environment" in
                let%bind commandEnv = Plan.commandEnv copts.spec plan task in
                let commandEnv = Scope.SandboxEnvironment.Bindings.render copts.cfg.buildCfg commandEnv in
                Environment.renderToShellSource ~header commandEnv
              ) in
              let%bind () =
                let filename = Path.(sandboxBin / "command-env") in
                writeData filename commandEnv
              in
              let%bind () =
                let filename = Path.(sandboxBin / "command-exec") in
                let commandExec = "#!/bin/bash\n" ^ commandEnv ^ "\nexec \"$@\"" in
                let%bind () = writeData filename commandExec in
                let%bind () = Fs.chmod 0o755 filename in
                return ()
              in
              return ()
            end
        else
          return ()
      in

      return ()

    in Perf.measureLwt ~label:"writing sandbox info cache" f

  let mtimeOf path =
    let open RunAsync.Syntax in
    let%bind stats = Fs.stat path in
    return stats.Unix.st_mtime

  let checkIsStale filesUsed =
    let open RunAsync.Syntax in
    let%bind checks =
      RunAsync.List.joinAll (
        let f {FileInfo. path; mtime} =
          match%lwt mtimeOf path with
          | Ok curMtime -> return (curMtime > mtime)
          | Error _ -> return true
        in
        List.map ~f filesUsed
      )
    in
    return (List.exists ~f:(fun x -> x) checks)

  let readCache (copts : CommonOptions.t) =
    let open RunAsync.Syntax in
    let f () =
      let cachePath = cachePath copts.cfg copts.spec in
      let f ic =
        let%lwt info = (Lwt_io.read_value ic : t Lwt.t) in
        if%bind checkIsStale info.filesUsed
        then return None
        else return (Some info)
      in
      try%lwt Lwt_io.with_file ~mode:Lwt_io.Input (Path.show cachePath) f
      with | Unix.Unix_error _ -> return None
    in Perf.measureLwt ~label:"reading sandbox info cache" f

  let make (copts : CommonOptions.t) =
    let open RunAsync.Syntax in
    let makeInfo () =
      let f () =

        let filesUsed = [] in

        let%bind solution, filesUsed =
          let path = EsyInstall.SandboxSpec.lockfilePath copts.spec in
          match%bind Lockfile.ofPath ~sandbox:copts.installSandbox path with
          | Some solution ->
            let%bind mtime = mtimeOf path in
            return (Some solution, {FileInfo. path; mtime}::filesUsed)
          | None -> return (None, filesUsed)
        in

        let%bind installation, filesUsed =
          let path = EsyInstall.SandboxSpec.installationPath copts.spec in
          match%bind EsyInstall.Installation.ofPath path with
          | Some installation ->
            let%bind mtime = mtimeOf path in
            return (Some installation, {FileInfo. path; mtime}::filesUsed)
          | None -> return (None, filesUsed)
        in

        let%bind scripts = Scripts.ofSandbox copts.spec in
        let%bind sandboxEnv = SandboxEnv.ofSandbox copts.spec in
        let%bind plan, filesUsed =
          match installation, solution with
          | Some installation, Some solution ->
            let%bind plan, filesUsedForPlan = Plan.make
              ~platform:System.Platform.host
              ~cfg:copts.cfg
              ~sandboxEnv
              ~solution
              ~installation
              ()
            in
            return (Some plan, filesUsed @ filesUsedForPlan)
          | _, None
          | None, _ -> return (None, filesUsed)
        in
        (* let%bind task, commandEnv, sandboxEnv = RunAsync.ofRun ( *)
        (*   let open Run.Syntax in *)
        (*   let%bind task = Task.ofSandbox sandbox in *)
        (*   let%bind commandEnv = *)
        (*     let%bind env = Task.commandEnv task in *)
        (*     return (Sandbox.Environment.Bindings.render sandbox.buildCfg env) *)
        (*   in *)
        (*   let%bind sandboxEnv = *)
        (*     let%bind env = Task.sandboxEnv task in *)
        (*     return (Sandbox.Environment.Bindings.render sandbox.buildCfg env) *)
        (*   in *)
        (*   return (task, commandEnv, sandboxEnv) *)
        (* ) in *)
        return {
          solution;
          installation;
          plan;
          spec = copts.spec;
          scripts;
          filesUsed;
        }
      in Perf.measureLwt ~label:"constructing sandbox info" f
    in

    match%bind readCache copts with
    | Some info ->
      return info
    | None ->
      let%bind info = makeInfo () in
      let%bind () = writeCache copts info in
      return info

  let resolvePackage ~pkgName copts info =
    let open RunAsync.Syntax in
    let%bind plan = plan info in
    let task =
      let open Option.Syntax in
      let%bind task = Plan.findTaskByName plan pkgName in
      return task
    in
    match task with
    | None -> errorf "package %s isn't built yet, run 'esy build'" pkgName
    | Some None -> errorf "package %s isn't built yet, run 'esy build'" pkgName
    | Some (Some task) ->
      let installPath =
        Scope.SandboxPath.toPath
          copts.CommonOptions.cfg.buildCfg
          (Plan.Task.installPath task)
      in
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

  let libraries ~ocamlfind ?builtIns ?task copts =
    let open RunAsync.Syntax in
    let ocamlpath =
      match task with
      | Some task ->
        Scope.SandboxPath.(Plan.Task.installPath task / "lib")
        |> Scope.SandboxPath.toPath copts.CommonOptions.cfg.buildCfg
        |> Path.show
      | None -> ""
    in
    let env =
      ChildProcess.CustomEnv Astring.String.Map.(
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
    let env = ChildProcess.CustomEnv Astring.String.Map.empty in
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

    let query ~ocamlfind ~task copts lib =
      let open RunAsync.Syntax in
      let ocamlpath =
        Scope.SandboxPath.(Plan.Task.installPath task / "lib")
        |> Scope.SandboxPath.toPath copts.CommonOptions.cfg.buildCfg
      in
      let env =
        ChildProcess.CustomEnv Astring.String.Map.(
          empty |>
          add "OCAMLPATH" (Path.show ocamlpath)
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
end

let resolvedPathTerm =
  let open Cmdliner in
  let parse v =
    match Path.ofString v with
    | Ok path ->
      if Path.isAbs path then
        Ok path
      else
        Ok Path.(EsyRuntime.currentWorkingDir // path |> normalize)
    | err -> err
  in
  let print = Path.pp in
  Arg.conv ~docv:"PATH" (parse, print)

(* let pkgPathTerm = *)
(*   let open Cmdliner in *)
(*   let doc = "Path to package." in *)
(*   Arg.( *)
(*     value *)
(*     & pos 0  (some resolvedPathTerm) None *)
(*     & info [] ~doc *)
(*   ) *)

let pkgIdTerm =
  let open Cmdliner in
  let pkgIdConv =
    let parse v =
      match EsyInstall.PackageId.parse v with
      | Ok v -> Ok v
      | Error err -> Error (`Msg err)
    in
    let print = EsyInstall.PackageId.pp in
    Arg.conv ~docv:"PATH" (parse, print)
  in
  let doc = "Package identifier." in
  Arg.(
    value
    & pos 0  (some pkgIdConv) None
    & info [] ~doc
  )

let withBuildTaskById
    ~(info : SandboxInfo.t)
    id
    f =
  let open RunAsync.Syntax in
  let%bind plan = SandboxInfo.plan info in
  match id with
  | Some id ->
    begin match Plan.findTaskById plan id with
    | Ok Some task -> f task
    | Ok None -> errorf "no build defined for %a" EsyInstall.PackageId.pp id
    | Error err -> Lwt.return (Error err)
    end
  | None ->
    begin match Plan.rootTask plan with
    | Some task -> f task
    | None -> errorf "no build defined for the root package"
    end

let buildPlan copts id () =
  let open RunAsync.Syntax in

  let%bind info = SandboxInfo.make copts in

  let f task =
    let json = Plan.Task.to_yojson task in
    let data = Yojson.Safe.pretty_to_string json in
    print_endline data;
    return ()
  in
  withBuildTaskById ~info id f

let buildShell (copts : CommonOptions.t) packagePath () =
  let open RunAsync.Syntax in

  let%bind (info : SandboxInfo.t) = SandboxInfo.make copts in

  let f task =
    let%bind plan = SandboxInfo.plan info in
    let%bind () =
      Plan.buildDependencies
        ~cfg:copts.cfg
        ~concurrency:EsyRuntime.concurrency
        plan
        task.Plan.Task.pkgId
    in
    let p =
      Plan.shell
        ~cfg:copts.cfg
        task
    in
    match%bind p with
    | Unix.WEXITED 0 -> return ()
    | Unix.WEXITED n
    | Unix.WSTOPPED n
    | Unix.WSIGNALED n -> exit n
  in withBuildTaskById ~info packagePath f

let buildPackage (copts : CommonOptions.t) packagePath () =
  let open RunAsync.Syntax in
  let%bind (info : SandboxInfo.t) = SandboxInfo.make copts in

  let f task =
    let%bind plan = SandboxInfo.plan info in
    let%bind () =
      Plan.buildDependencies
        ~cfg:copts.cfg
        ~concurrency:EsyRuntime.concurrency
        plan
        task.Plan.Task.pkgId
    in
    Plan.build
      ~cfg:copts.cfg
      ~force:true
      plan
      task.Plan.Task.pkgId
  in
  withBuildTaskById ~info packagePath f

let build ?(buildOnly=true) (copts : CommonOptions.t) cmd () =
  let open RunAsync.Syntax in
  let%bind info = SandboxInfo.make copts in
  let%bind plan = SandboxInfo.plan info in
  let%bind solution = SandboxInfo.solution info in
  let root = Solution.Package.id (Solution.root solution) in
  let%bind () =
    Plan.buildDependencies
      ~cfg:copts.cfg
      ~concurrency:EsyRuntime.concurrency
      plan
      root
  in
  begin match cmd with
  | None ->
    Plan.build
      ~cfg:copts.cfg
      ~force:true
      ~quiet:true
      ~buildOnly
      plan
      root
  | Some cmd ->
    begin match%bind RunAsync.ofRun (Plan.findTaskById plan root) with
    | None -> errorf "root package doesn't define any build"
    | Some task ->
      let p =
        Plan.exec
          ~cfg:copts.cfg
          task
          cmd
      in
      match%bind p with
      | Unix.WEXITED 0 -> return ()
      | Unix.WEXITED n
      | Unix.WSTOPPED n
      | Unix.WSIGNALED n -> exit n
    end
  end

let makeEnvCommand ~computeEnv ~header copts asJson packagePath () =
  let open RunAsync.Syntax in

  let%bind info = SandboxInfo.make copts in

  let f (task : Plan.Task.t) =
    let%bind env = computeEnv copts info task in
    let%bind source = RunAsync.ofRun (
      let open Run.Syntax in
      let header = header task in
      if asJson
      then
        let%bind env = Run.ofStringError (Environment.Bindings.eval env) in
        Ok (
          env
          |> Environment.to_yojson
          |> Yojson.Safe.pretty_to_string)
      else
        Environment.renderToShellSource
          ~header
          env
      ) in
    let%lwt () = Lwt_io.print source in
    return ()
  in withBuildTaskById ~info packagePath f

let buildEnv =
  let header (task : Plan.Task.t) =
    Format.asprintf
      "# Build environment for %s@%a"
      task.name Version.pp task.version
  in
  let computeEnv (copts : CommonOptions.t) (info : SandboxInfo.t) task =
    let open RunAsync.Syntax in
    let%bind plan = SandboxInfo.plan info in
    let%bind env = RunAsync.ofRun (Plan.buildEnv copts.spec plan task) in
    let env = Scope.SandboxEnvironment.Bindings.render copts.cfg.buildCfg env in
    return env
  in
  makeEnvCommand ~computeEnv ~header

let commandEnv =
  let open RunAsync.Syntax in
  let header (task : Plan.Task.t) =
    Format.asprintf
      "# Command environment for %s@%a"
      task.name Version.pp task.version
  in
  let computeEnv (copts : CommonOptions.t) (info : SandboxInfo.t) task =
    let%bind plan = SandboxInfo.plan info in
    let%bind env = RunAsync.ofRun (Plan.commandEnv copts.spec plan task) in
    let env = Scope.SandboxEnvironment.Bindings.render copts.cfg.buildCfg env in
    return (Environment.current @ env)
  in
  makeEnvCommand ~computeEnv ~header

let sandboxEnv =
  let open RunAsync.Syntax in
  let header (task : Plan.Task.t) =
    Format.asprintf
      "# Sandbox environment for %s@%a"
      task.name Version.pp task.version
  in
  let computeEnv (copts : CommonOptions.t) (info : SandboxInfo.t) task =
    let%bind plan = SandboxInfo.plan info in
    let%bind env = RunAsync.ofRun (Plan.execEnv copts.spec plan task) in
    let env = Scope.SandboxEnvironment.Bindings.render copts.cfg.buildCfg env in
    return (Environment.current @ env)
  in
  makeEnvCommand ~computeEnv ~header

let makeExecCommand
    ?(checkIfDependenciesAreBuilt=false)
    ~env
    ~(copts : CommonOptions.t)
    ~info
    cmd
    ()
  =
  let open RunAsync.Syntax in

  let%bind plan = SandboxInfo.plan info in
  let task =
    match Plan.rootTask plan with
    | None -> failwith "TODO"
    | Some task -> task
  in

  let%bind () =
    if checkIfDependenciesAreBuilt
    then
      Plan.buildDependencies
        ~cfg:copts.cfg
        ~concurrency:EsyRuntime.concurrency
        plan
        task.Plan.Task.pkgId
    else return ()
  in

  let%bind env = RunAsync.ofRun (
    match env with
    | `CommandEnv -> Plan.commandEnv copts.spec plan task
    | `SandboxEnv -> Plan.execEnv copts.spec plan task
  ) in

  let%bind env = RunAsync.ofStringError (
    let open Result.Syntax in
    let env =
      Scope.SandboxEnvironment.Bindings.render
      copts.cfg.buildCfg
      env
    in
    let env = Environment.current @ env in
    let%bind env = Environment.Bindings.eval env in
    return (ChildProcess.CustomEnv env)
  ) in

  let cmd =
    let tool, args = Cmd.getToolAndArgs cmd in
    match tool with
    | "esy" -> Cmd.(v (p EsyRuntime.currentExecutable) |> addArgs args)
    | _ -> cmd
  in

  let%bind status =
    ChildProcess.runToStatus
      ~env
      ~resolveProgramInEnv:true
      ~stderr:(`FD_copy Unix.stderr)
      ~stdout:(`FD_copy Unix.stdout)
      ~stdin:(`FD_copy Unix.stdin)
      cmd
  in
  match status with
  | Unix.WEXITED n
  | Unix.WSTOPPED n
  | Unix.WSIGNALED n -> exit n

let exec (copts : CommonOptions.t) cmd () =
  let open RunAsync.Syntax in
  let%bind (info : SandboxInfo.t) = SandboxInfo.make copts in
  let%bind () =
    let%bind plan = SandboxInfo.plan info in
    let task =
      match Plan.rootTask plan with
      | None -> failwith "TODO"
      | Some task -> task
    in
    let installPath =
      Scope.SandboxPath.toPath
        copts.cfg.buildCfg
        (Plan.Task.installPath task)
    in
    if%bind Fs.exists installPath then
      return ()
    else
      build ~buildOnly:false copts None ()
  in
  makeExecCommand
    ~env:`SandboxEnv
    ~copts
    ~info
    cmd
    ()

let devExec (copts : CommonOptions.t) cmd () =
  let open RunAsync.Syntax in
  let%bind (info : SandboxInfo.t) = SandboxInfo.make copts in
  let%bind plan = SandboxInfo.plan info in
  let task =
    match Plan.rootTask plan with
    | None -> failwith "TODO"
    | Some task -> task
  in
  let%bind cmd = RunAsync.ofRun (
    let open Run.Syntax in
    let tool, args = Cmd.getToolAndArgs cmd in
    let script =
      Scripts.find
        tool
        info.scripts
    in
    let renderCommand (cmd : BuildManifest.Command.t) =
      match cmd with
      | Parsed args ->
        let%bind args =
          Result.List.map
            ~f:(Plan.Task.renderExpression ~cfg:copts.cfg task)
            args
        in
        return (Cmd.ofListExn args)
      | Unparsed line ->
        let%bind string =
          Plan.Task.renderExpression
            ~cfg:copts.cfg
            task line
        in
        let%bind args = ShellSplit.split string in
        return (Cmd.ofListExn args)
    in
    match script with
    | None -> return cmd
    | Some {command; _} ->
      let%bind command = renderCommand command in
      return (Cmd.addArgs args command)
  ) in
  makeExecCommand
    ~checkIfDependenciesAreBuilt:true
    ~env:`CommandEnv
    ~copts
    ~info
    cmd
    ()

let devShell copts () =
  let open RunAsync.Syntax in
  let shell =
    try Sys.getenv "SHELL"
    with Not_found -> "/bin/bash"
  in
  let%bind (info : SandboxInfo.t) = SandboxInfo.make copts in
  makeExecCommand
    ~env:`CommandEnv
    ~copts
    ~info
    (Cmd.v shell)
    ()

let makeLsCommand ~computeTermNode ~includeTransitive (info: SandboxInfo.t) =
  let open RunAsync.Syntax in

  let%bind plan = SandboxInfo.plan info in
  let%bind solution = SandboxInfo.solution info in
  let seen = ref PackageId.Set.empty in
  let root = Solution.root solution in

  let () =
    let f pkg _deps () =
      Format.printf "%a@." Solution.Package.pp pkg;
      ()
    in
    Solution.fold ~f ~init:() solution
  in

  let rec draw pkg =
    let id = Solution.Package.id pkg in
    if PackageId.Set.mem id !seen then
      return None
    else (
      let isRoot = Solution.isRoot pkg solution in
      seen := PackageId.Set.add id !seen;
      match%bind RunAsync.ofRun (Plan.findTaskById plan id) with
      | None -> return None
      | Some task ->
        let%bind children =
          if not includeTransitive && not isRoot then
            return []
          else
            let dependencies =
              let traverse =
                if isRoot
                then Solution.traverseWithDevDependencies
                else Solution.traverse
              in
              Solution.dependencies ~traverse pkg solution
            in
            dependencies
            |> List.map ~f:draw
            |> RunAsync.List.joinAll
        in
        let children = children |> List.filterNone in
        computeTermNode task children
    )
  in
  match%bind draw root with
  | Some tree -> return (print_endline (TermTree.render tree))
  | None -> return ()

let formatPackageInfo ~built:(built : bool)  (task : Plan.Task.t) =
  let open RunAsync.Syntax in
  let version = Chalk.grey ("@" ^ Version.show task.version) in
  let status =
    match task.sourceType, built with
    | BuildManifest.SourceType.Immutable, true ->
      Chalk.green "[built]"
    | _, _ ->
      Chalk.blue "[build pending]"
  in
  let line = Printf.sprintf "%s%s %s" task.name version status in
  return line

let taskIsBuilt copts task =
  let installPath = Plan.Task.installPath task in
  Fs.exists (Scope.SandboxPath.toPath copts.CommonOptions.cfg.buildCfg installPath)

let lsBuilds (copts : CommonOptions.t) includeTransitive () =
  let open RunAsync.Syntax in

  let%bind (info : SandboxInfo.t) = SandboxInfo.make copts in

  let computeTermNode task children =
    let%bind built = taskIsBuilt copts task in
    let%bind line = formatPackageInfo ~built task in
    return (Some (TermTree.Node { line; children; }))
  in
  makeLsCommand ~computeTermNode ~includeTransitive info

let lsLibs copts includeTransitive () =
  let open RunAsync.Syntax in

  let%bind (info : SandboxInfo.t) = SandboxInfo.make copts in

  let%bind ocamlfind =
    let%bind p = SandboxInfo.ocamlfind copts info in
    return Path.(p / "bin" / "ocamlfind")
  in
  let%bind builtIns = SandboxInfo.libraries ~ocamlfind copts in

  let computeTermNode (task: Plan.Task.t) children =
    let%bind built = taskIsBuilt copts task in
    let%bind line = formatPackageInfo ~built task in

    let%bind libs =
      if built then
        SandboxInfo.libraries ~ocamlfind ~builtIns ~task copts
      else
        return []
    in

    let libs =
      libs
      |> List.map ~f:(fun lib ->
          let line = Chalk.yellow(lib) in
          TermTree.Node { line; children = []; }
        )
    in

    return (Some (TermTree.Node { line; children = libs @ children; }))
  in
  makeLsCommand ~computeTermNode ~includeTransitive info

let lsModules copts only () =
  let open RunAsync.Syntax in

  let%bind (info : SandboxInfo.t) = SandboxInfo.make copts in
  let%bind solution = SandboxInfo.solution info in
  let root = Solution.root solution in

  let%bind ocamlfind =
    let%bind p = SandboxInfo.ocamlfind copts info in
    return Path.(p / "bin" / "ocamlfind")
  in
  let%bind ocamlobjinfo =
    let%bind p = SandboxInfo.ocaml copts info in
    return Path.(p / "bin" / "ocamlobjinfo")
  in
  let%bind builtIns = SandboxInfo.libraries ~ocamlfind copts in

  let formatLibraryModules ~task lib =
    let%bind meta = SandboxInfo.Findlib.query ~ocamlfind ~task copts lib in
    let open SandboxInfo.Findlib in

    if String.length(meta.archive) == 0 then
      let description = Chalk.dim(meta.description) in
      return [TermTree.Node { line=description; children=[]; }]
    else begin
      Path.ofString (meta.location ^ Path.dirSep ^ meta.archive) |> function
      | Ok archive ->
        if%bind Fs.exists archive then begin
          let archive = Path.show archive in
          let%bind lines =
            SandboxInfo.modules ~ocamlobjinfo archive
          in

          let modules =
            let isPublicModule name =
              not (Astring.String.is_infix ~affix:"__" name)
            in
            let toTermNode name =
              let line = Chalk.cyan name in
              TermTree.Node { line; children=[]; }
            in
            lines
            |> List.filter ~f:isPublicModule
            |> List.map ~f:toTermNode
          in

          return modules
        end else
          return []
      | Error `Msg msg -> error msg
    end
  in

  let computeTermNode (task: Plan.Task.t) children =
    let%bind built = taskIsBuilt copts task in
    let%bind line = formatPackageInfo ~built task in

    let%bind libs =
      if built then
        SandboxInfo.libraries ~ocamlfind ~builtIns ~task copts
      else
        return []
    in

    let isNotRoot = PackageId.compare task.pkgId (Solution.Package.id root) <> 0 in
    let constraintsSet = List.length only <> 0 in
    let noMatchedLibs = List.length (List.intersect only libs) = 0 in

    if isNotRoot && constraintsSet && noMatchedLibs then
      return None
    else
      let%bind libs =
        libs
        |> List.filter ~f:(fun lib ->
            if List.length only = 0 then
              true
            else
              List.mem lib ~set:only
          )
        |> List.map ~f:(fun lib ->
            let line = Chalk.yellow(lib) in
            let%bind children =
              formatLibraryModules ~task lib
            in
            return (TermTree.Node { line; children; })
          )
        |> RunAsync.List.joinAll
      in

      return (Some (TermTree.Node { line; children = libs @ children; }))
  in
  makeLsCommand ~computeTermNode ~includeTransitive:false info

let getSandboxSolution installSandbox =
  let open EsyInstall in
  let open RunAsync.Syntax in
  let%bind solution = Solver.solve installSandbox in
  let lockfilePath = SandboxSpec.lockfilePath installSandbox.Sandbox.spec in
  let%bind () =
    Lockfile.toPath ~sandbox:installSandbox ~solution lockfilePath
  in
  return solution

let solve {CommonOptions. installSandbox; _} () =
  let open RunAsync.Syntax in
  let%bind _ : Solution.t = getSandboxSolution installSandbox in
  return ()

let fetch {CommonOptions. installSandbox = sandbox; _} () =
  let open EsyInstall in
  let open RunAsync.Syntax in
  let lockfilePath = SandboxSpec.lockfilePath sandbox.Sandbox.spec in
  match%bind Lockfile.ofPath ~sandbox lockfilePath with
  | Some solution -> Fetch.fetch ~sandbox solution
  | None -> error "no lockfile found, run 'esy solve' first"

let solveAndFetch ({CommonOptions. installSandbox = sandbox; _} as copts) () =
  let open EsyInstall in
  let open RunAsync.Syntax in
  let lockfilePath = SandboxSpec.lockfilePath sandbox.Sandbox.spec in
  match%bind Lockfile.ofPath ~sandbox lockfilePath with
  | Some solution ->
    if%bind Fetch.isInstalled ~sandbox solution
    then return ()
    else fetch copts ()
  | None ->
    let%bind () = solve copts () in
    let%bind () = fetch copts () in
    return ()

let add ({CommonOptions. installSandbox; _} as copts) (reqs : string list) () =
  let open EsyInstall in
  let open RunAsync.Syntax in
  let aggOpamErrorMsg =
    "The esy add command doesn't work with opam sandboxes. "
    ^ "Please send a pull request to fix this!"
  in

  let%bind reqs = RunAsync.ofStringError (
    Result.List.map ~f:Req.parse reqs
  ) in

  let addReqs origDeps =
    let open Package.Dependencies in
    match origDeps with
    | NpmFormula prevReqs -> return (NpmFormula (reqs @ prevReqs))
    | OpamFormula _ -> error aggOpamErrorMsg
  in

  let%bind installSandbox =
    let%bind combinedDeps = addReqs installSandbox.root.dependencies in
    let%bind sbDeps = addReqs installSandbox.dependencies in
    let root = { installSandbox.root with dependencies = combinedDeps } in
    return { installSandbox with root; dependencies = sbDeps }
  in

  let copts = {copts with installSandbox} in

  let%bind solution = getSandboxSolution installSandbox in
  let%bind () = fetch copts () in

  let%bind addedDependencies, configPath =
    let records =
      let f (record : Solution.Package.t) _ map =
        StringMap.add record.name record map
      in
      Solution.fold ~f ~init:StringMap.empty solution
    in
    let addedDependencies =
      let f {Req. name; _} =
        match StringMap.find name records with
        | Some record ->
          let constr =
            match record.Solution.Package.version with
            | Version.Npm version ->
              SemverVersion.Formula.DNF.show
                (SemverVersion.caretRangeOfVersion version)
            | Version.Opam version ->
              OpamPackage.Version.to_string version
            | Version.Source _ ->
              Version.show record.Solution.Package.version
          in
          name, `String constr
        | None -> assert false
      in
      List.map ~f reqs
    in
    let%bind path =
      let spec = copts.installSandbox.Sandbox.spec in
      match spec.manifest with
      | ManifestSpec.One (Esy, fname) -> return Path.(spec.SandboxSpec.path / fname)
      | One (Opam, _) -> error aggOpamErrorMsg
      | ManyOpam -> error aggOpamErrorMsg
      in
      return (addedDependencies, path)
    in
    let%bind json =
      let keyToUpdate = "dependencies" in
      let%bind json = Fs.readJsonFile configPath in
        let%bind json =
          RunAsync.ofStringError (
            let open Result.Syntax in
            let%bind items = Json.Decode.assoc json in
            let%bind items =
              let f (key, json) =
                if key = keyToUpdate
                then
                    let%bind dependencies =
                      Json.Decode.assoc json in
                    let dependencies =
                      Json.mergeAssoc dependencies
                        addedDependencies in
                    return
                      (key, (`Assoc dependencies))
                else return (key, json)
              in
              Result.List.map ~f items
            in
            let json = `Assoc items
            in return json
          ) in
        return json
      in
      let%bind () = Fs.writeJsonFile ~json configPath in
      return ()

let exportBuild (copts : CommonOptions.t) buildPath () =
  let outputPrefixPath = Path.(EsyRuntime.currentWorkingDir / "_export") in
  Plan.exportBuild ~outputPrefixPath ~cfg:copts.cfg buildPath

let exportDependencies (copts : CommonOptions.t) () =
  let open RunAsync.Syntax in

  let%bind info = SandboxInfo.make copts in
  let%bind plan = SandboxInfo.plan info in
  let%bind solution = SandboxInfo.solution info in

  let exportBuild (_, pkg) =
    let task =
      RunAsync.ofRun (Plan.findTaskById plan (Solution.Package.id pkg))
    in
    match%bind task with
    | None -> return ()
    | Some task ->
      let%lwt () = Logs_lwt.app (fun m -> m "Exporting %s@%a" pkg.name Version.pp pkg.version) in
      let buildPath = Scope.SandboxPath.toPath copts.cfg.buildCfg
      (Plan.Task.installPath task) in
      if%bind Fs.exists buildPath
      then
        let outputPrefixPath = Path.(EsyRuntime.currentWorkingDir / "_export") in
        Plan.exportBuild ~outputPrefixPath ~cfg:copts.cfg buildPath
      else (
        errorf
          "%s@%a was not built, run 'esy build' first"
          pkg.name Version.pp pkg.version
      )
  in

  RunAsync.List.mapAndWait
    ~concurrency:8
    ~f:exportBuild
    (Solution.allDependenciesBFS (Solution.root solution) solution)

let importBuild (copts : CommonOptions.t) fromPath buildPaths () =
  let open RunAsync.Syntax in
  let%bind buildPaths = match fromPath with
  | Some fromPath ->
    let%bind lines = Fs.readFile fromPath in
    return (
      buildPaths @ (
      lines
      |> String.split_on_char '\n'
      |> List.filter ~f:(fun line -> String.trim line <> "")
      |> List.map ~f:(fun line -> Path.v line))
    )
  | None -> return buildPaths
  in

  RunAsync.List.mapAndWait
    ~concurrency:8
    ~f:(fun path -> Plan.importBuild ~cfg:copts.cfg path)
    buildPaths

let importDependencies (copts : CommonOptions.t) fromPath () =
  let open RunAsync.Syntax in

  let%bind (info : SandboxInfo.t) = SandboxInfo.make copts in
  let%bind solution = SandboxInfo.solution info in
  let%bind plan = SandboxInfo.plan info in

  let fromPath = match fromPath with
    | Some fromPath -> fromPath
    | None -> Path.(copts.cfg.buildCfg.projectPath / "_export")
  in

  let importBuild (_direct, pkg) =
    match%bind RunAsync.ofRun (Plan.findTaskById plan (Solution.Package.id pkg)) with
    | Some task ->
      let installPath = Scope.SandboxPath.toPath copts.cfg.buildCfg (Plan.Task.installPath task) in
      if%bind Fs.exists installPath
      then return ()
      else (
        let id = task.id in
        let pathDir = Path.(fromPath / id) in
        let pathTgz = Path.(fromPath / (id ^ ".tar.gz")) in
        if%bind Fs.exists pathDir
        then Plan.importBuild ~cfg:copts.cfg pathDir
        else if%bind Fs.exists pathTgz
        then Plan.importBuild ~cfg:copts.cfg pathTgz
        else
          let%lwt () =
            Logs_lwt.warn(fun m -> m "no prebuilt artifact found for %s" id)
          in return ()
      )
    | None -> return ()
  in

  RunAsync.List.mapAndWait
    ~concurrency:16
    ~f:importBuild
    (Solution.allDependenciesBFS (Solution.root solution) solution)

let release copts () =
  let open RunAsync.Syntax in
  let%bind info = SandboxInfo.make copts in
  let%bind installation = SandboxInfo.installation info in
  let%bind solution = SandboxInfo.solution info in

  let%bind outputPath =
    let outputDir = "_release" in
    let outputPath = Path.(copts.cfg.buildCfg.projectPath / outputDir) in
    let%bind () = Fs.rmPath outputPath in
    return outputPath
  in

  let%bind () = build copts None () in

  let%bind ocamlopt =
    let%bind p = SandboxInfo.ocaml copts info in
    return Path.(p / "bin" / "ocamlopt")
  in

  let%bind sandboxEnv = SandboxEnv.ofSandbox copts.spec in

  NpmRelease.make
    ~sandboxEnv
    ~solution:solution
    ~installation:installation
    ~ocamlopt
    ~esyInstallRelease:EsyRuntime.esyInstallRelease
    ~outputPath
    ~concurrency:EsyRuntime.concurrency
    ~cfg:copts.CommonOptions.cfg
    ()

let makeCommand
  ?(header=`Standard)
  ?(sdocs=Cmdliner.Manpage.s_common_options)
  ?docs
  ?doc
  ?(version=EsyRuntime.version)
  ?(exits=Cmdliner.Term.default_exits)
  ~name
  cmd =
  let info =
    Cmdliner.Term.info
      ~exits
      ~sdocs
      ?docs
      ?doc
      ~version
      name
  in

  let printHeader () =
    match header with
    | `Standard -> Logs_lwt.app (fun m -> m "%s %s" name version);
    | `No -> Lwt.return ()
  in

  let cmd =
    let f comp =
      runAsyncToCmdlinerRet (
        printHeader ();%lwt
        comp
      )
    in
    Cmdliner.Term.(ret (app (const f) cmd))
  in

  cmd, info

let makeAlias command alias =
  let term, info = command in
  let name = Cmdliner.Term.name info in
  let doc = Printf.sprintf "An alias for $(b,%s) command" name in
  term, Cmdliner.Term.info alias ~version:EsyRuntime.version ~doc

let makeCommands ~sandbox () =
  let open Cmdliner in

  let commonOpts = CommonOptions.term sandbox in

  let defaultCommand =
    let run copts cmd () =
      let open RunAsync.Syntax in
      match cmd with
      | Some cmd ->
        devExec copts cmd ()
      | None ->
        Logs_lwt.app (fun m -> m "esy %s" EsyRuntime.version);%lwt
        let%bind () = solveAndFetch copts () in
        build copts None ()
    in
    let cmdTerm =
      Cli.cmdOptionTerm
        ~doc:"Command to execute within the sandbox environment."
        ~docv:"COMMAND"
    in
    makeCommand
      ~header:`No
      ~name:"esy"
      ~doc:"package.json workflow for native development with Reason/OCaml"
      Term.(const run $ commonOpts $ cmdTerm $ Cli.setupLogTerm)
  in

  let commands =

    let buildCommand =

      let run copts cmd () =
        let%lwt () =
          match cmd with
          | None -> Logs_lwt.app (fun m -> m "esy build %s" EsyRuntime.version)
          | Some _ -> Lwt.return ()
        in
        build ~buildOnly:true copts cmd ()
      in

      makeCommand
        ~header:`No
        ~name:"build"
        ~doc:"Build the entire sandbox"
        Term.(
          const run
          $ commonOpts
          $ Cli.cmdOptionTerm
              ~doc:"Command to execute within the build environment."
              ~docv:"COMMAND"
          $ Cli.setupLogTerm
        )
    in

    let installCommand =
      makeCommand
        ~name:"install"
        ~doc:"Solve & fetch dependencies"
        Term.(
          const solveAndFetch
          $ commonOpts
          $ Cli.setupLogTerm
        )
    in

    [
    (* commands *)

    installCommand;
    buildCommand;

    makeCommand
      ~header:`No
      ~name:"build-plan"
      ~doc:"Print build plan to stdout"
      Term.(
        const buildPlan
        $ commonOpts
        $ pkgIdTerm
        $ Cli.setupLogTerm
      );

    makeCommand
      ~name:"build-shell"
      ~doc:"Enter the build shell"
      Term.(
        const buildShell
        $ commonOpts
        $ pkgIdTerm
        $ Cli.setupLogTerm
      );

    makeCommand
      ~name:"build-package"
      ~doc:"Build specified package"
      Term.(
        const buildPackage
        $ commonOpts
        $ pkgIdTerm
        $ Cli.setupLogTerm
      );

    makeCommand
      ~header:`No
      ~name:"shell"
      ~doc:"Enter esy sandbox shell"
      Term.(
        const devShell
        $ commonOpts
        $ Cli.setupLogTerm
      );

    makeCommand
      ~header:`No
      ~name:"build-env"
      ~doc:"Print build environment to stdout"
      Term.(
        const buildEnv
        $ commonOpts
        $ Arg.(value & flag & info ["json"]  ~doc:"Format output as JSON")
        $ pkgIdTerm
        $ Cli.setupLogTerm
      );

    makeCommand
      ~header:`No
      ~name:"command-env"
      ~doc:"Print command environment to stdout"
      Term.(
        const commandEnv
        $ commonOpts
        $ Arg.(value & flag & info ["json"]  ~doc:"Format output as JSON")
        $ pkgIdTerm
        $ Cli.setupLogTerm
      );

    makeCommand
      ~header:`No
      ~name:"sandbox-env"
      ~doc:"Print sandbox environment to stdout"
      Term.(
        const sandboxEnv
        $ commonOpts
        $ Arg.(value & flag & info ["json"]  ~doc:"Format output as JSON")
        $ pkgIdTerm
        $ Cli.setupLogTerm
      );

    makeCommand
      ~name:"ls-builds"
      ~doc:"Output a tree of packages in the sandbox along with their status"
      Term.(
        const lsBuilds
        $ commonOpts
        $ Arg.(
            value
            & flag
            & info ["T"; "include-transitive"] ~doc:"Include transitive dependencies")
        $ Cli.setupLogTerm
      );

    makeCommand
      ~name:"ls-libs"
      ~doc:"Output a tree of packages along with the set of libraries made available by each package dependency."
      Term.(
        const lsLibs
        $ commonOpts
        $ Arg.(
            value
            & flag
            & info ["T"; "include-transitive"] ~doc:"Include transitive dependencies")
        $ Cli.setupLogTerm
      );

    makeCommand
      ~name:"ls-modules"
      ~doc:"Output a tree of packages along with the set of libraries and modules made available by each package dependency."
      Term.(
        const lsModules
        $ commonOpts
        $ Arg.(
            value
            & (pos_all string [])
            & info [] ~docv:"LIB" ~doc:"Output modules only for specified lib(s)")
        $ Cli.setupLogTerm
      );

    makeCommand
      ~name:"export-dependencies"
      ~doc:"Export sandbox dependendencies as prebuilt artifacts"
      Term.(
        const exportDependencies
        $ commonOpts
        $ Cli.setupLogTerm
      );

    makeCommand
      ~name:"import-dependencies"
      ~doc:"Import sandbox dependencies"
      Term.(
        const importDependencies
        $ commonOpts
        $ Arg.(
            value
            & pos 0  (some resolvedPathTerm) None
            & info [] ~doc:"Path with builds."
          )
        $ Cli.setupLogTerm
      );

    makeCommand
      ~header:`No
      ~name:"x"
      ~doc:"Execute command as if the package is installed"
      Term.(
        const exec
        $ commonOpts
        $ Cli.cmdTerm
            ~doc:"Command to execute within the sandbox environment."
            ~docv:"COMMAND"
        $ Cli.setupLogTerm
      );

    makeCommand
      ~name:"export-build"
      ~doc:"Export build from the store"
      Term.(
        const exportBuild
        $ commonOpts
        $ Arg.(
            required
            & pos 0  (some resolvedPathTerm) None
            & info [] ~doc:"Path with builds."
          )
        $ Cli.setupLogTerm
      );

    makeCommand
      ~name:"import-build"
      ~doc:"Import build into the store"
      Term.(
        const importBuild
        $ commonOpts
        $ Arg.(
            value
            & opt (some resolvedPathTerm) None
            & info ["from"; "f"] ~docv:"FROM"
          )
        $ Arg.(
            value
            & pos_all resolvedPathTerm []
            & info [] ~docv:"BUILD"
          )
        $ Cli.setupLogTerm
      );

    makeCommand
      ~name:"add"
      ~doc:"Add a new dependency"
      Term.(
        const add
        $ commonOpts
        $ Arg.(
            non_empty
            & pos_all string []
            & info [] ~docv:"PACKAGE" ~doc:"Package to install"
          )
        $ Cli.setupLogTerm
      );

    makeCommand
      ~name:"solve"
      ~doc:"Solve dependencies and store the solution as a lockfile"
      Term.(
        const solve
        $ commonOpts
        $ Cli.setupLogTerm
      );

    makeCommand
      ~name:"fetch"
      ~doc:"Fetch dependencies using the solution in a lockfile"
      Term.(
        const fetch
        $ commonOpts
        $ Cli.setupLogTerm
      );

    makeCommand
      ~name:"release"
      ~doc:"Produce npm package with prebuilt artifacts"
      Term.(
        const release
        $ commonOpts
        $ Cli.setupLogTerm
      );

    makeCommand
      ~name:"help"
      ~doc:"Show this message and exit"
      Term.(ret (
        const (fun () -> `Help (`Auto, None))
        $ const ()
      ));

    makeCommand
      ~name:"version"
      ~doc:"Print esy version and exit"
      Term.(
        const (fun () -> print_endline EsyRuntime.version; RunAsync.return())
        $ const ()
      );

    (* aliases *)
    makeAlias buildCommand "b";
    makeAlias installCommand "i";
  ] in

  defaultCommand, commands

let checkSymlinks () =
  if Unix.has_symlink () == false then begin
    print_endline ("ERROR: Unable to create symlinks. Missing SeCreateSymbolicLinkPrivilege.");
    print_endline ("");
    print_endline ("Esy must be ran as an administrator on Windows, because it uses symbolic links.");
    print_endline ("Open an elevated command shell by right-clicking and selecting 'Run as administrator', and try esy again.");
    print_endline("");
    print_endline ("For more info, see https://github.com/esy/esy/issues/389");
    exit 1;
  end

let () =

  let () = checkSymlinks () in

  let argv, commandName, sandbox =
    let argv = Array.to_list Sys.argv in

    let sandbox, argv =
      match argv with
      | [] -> None, argv
      | prg::elem::rest when String.get elem 0 = '@' ->
        let sandbox = String.sub elem 1 (String.length elem - 1) in
        Some (Path.v sandbox), prg::rest
      | _ -> None, argv
    in

    let commandName, argv =
      match argv with
      | [] -> None, argv
      | _prg::elem::_rest when String.get elem 0 = '-' -> None, argv
      | _prg::elem::_rest -> Some elem, argv
      | _ -> None, argv
    in

    Array.of_list argv, commandName, sandbox
  in

  let defaultCommand, commands = makeCommands ~sandbox () in

  let hasCommand name =
    List.exists
      ~f:(fun (_cmd, info) -> Cmdliner.Term.name info = name)
      commands
  in

  let runCmdliner argv =
    Cmdliner.Term.(exit @@ eval_choice ~argv defaultCommand commands);
  in

  match commandName with

  (*
   * Fixup invocations for commands which pass their arguments through to other
   * executables.
   *
   * TODO: currently this is implemented in a way which prevents common options
   * (like --sandbox-path or --prefix-path) from working for these commands.
   * This should be fixed.
   *)
  | Some "x"
  | Some "b"
  | Some "build" ->
    let argv =
      match Array.to_list argv with
      | (_prg::_command::"--help"::[]) as argv -> argv
      | prg::command::rest -> prg::command::"--"::rest
      | argv -> argv
    in
    let argv = Array.of_list argv in
    runCmdliner argv

  | Some "" ->
    runCmdliner argv

  (*
   * Fix
   *
   *   esy <anycommand>
   *
   * for cmdliner by injecting "--" so that users are not requied to do that.
   *)
  | Some commandName ->
    if hasCommand commandName
    then runCmdliner argv
    else
      let argv =
        match Array.to_list argv with
        | prg::rest -> prg::"--"::rest
        | argv -> argv
      in
      let argv = Array.of_list argv in
      runCmdliner argv

  | _ -> runCmdliner argv
