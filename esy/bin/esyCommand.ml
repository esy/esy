open Esy

module Version = EsyInstall.Version

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

  let resolveCommand req =
    let open RunAsync.Syntax in
    let%bind path = resolve req in
    return (path |> Cmd.p)

  let fastreplacestringCommand =
    resolveCommand "../../../../bin/fastreplacestring"

  let esyBuildPackageCommand =
    resolveCommand "../../esy-build-package/bin/esyBuildPackageCommand.exe"

  let esyInstallRelease =
    resolve "../../../../bin/esyInstallRelease.js"

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

  let resolveSandoxPath () =
    let open RunAsync.Syntax in

    let%bind currentPath = RunAsync.ofRun (Path.current ()) in

    let rec climb path =
      if%bind Sandbox.isSandbox path
      then return path
      else
        let parent = Path.parent path in
        if not (Path.compare path parent = 0)
        then climb (Path.parent path)
        else errorf "No sandbox found (from %a and up)" Path.ppPretty currentPath
    in
    climb currentPath

  let term sandboxPath =

    let sandboxPath =
      match sandboxPath with
      | Some sandboxPath ->
        RunAsync.return (
          if Path.isAbs sandboxPath
          then sandboxPath
          else Path.(EsyRuntime.currentWorkingDir // sandboxPath)
        )
      | None -> resolveSandoxPath ()
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
          let%bind esyBuildPackageCommand =
            let%bind cmd = EsyRuntime.esyBuildPackageCommand in
            return (Cmd.v cmd)
          in
          let%bind fastreplacestringCommand =
            let%bind cmd = EsyRuntime.fastreplacestringCommand in
            return (Cmd.v cmd)
          in
          RunAsync.ofRun (
            Config.make
              ~installCfg
              ~esyBuildPackageCommand
              ~fastreplacestringCommand
              ~esyVersion:EsyRuntime.version
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
    spec: EsyInstall.SandboxSpec.t;
    sandbox : Sandbox.t;
    task : Task.t;
    commandEnv : Environment.Bindings.t;
    sandboxEnv : Environment.Bindings.t;
    info : Sandbox.info;
  }

  let cachePath (cfg : Config.t) (spec : EsyInstall.SandboxSpec.t) =
    let hash = [
      Path.show cfg.storePath;
      Path.show spec.path;
      cfg.esyVersion
    ]
      |> String.concat "$$"
      |> Digest.string
      |> Digest.to_hex
    in
    Path.(EsyInstall.SandboxSpec.cachePath spec / ("sandbox-" ^ hash))

  let writeCache (cfg : Config.t) (info : t) =
    let open RunAsync.Syntax in
    let f () =

      let%bind () =
        let f oc =
          let%lwt () = Lwt_io.write_value oc info in
          let%lwt () = Lwt_io.flush oc in
          return ()
        in
        let cachePath = cachePath cfg info.spec in
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
          let sandboxBin = Path.(info.spec.path / "node_modules" / ".cache" / "_esy" / "build" / "bin") in
          let%bind () = Fs.createDir sandboxBin in

          let%bind commandEnv = RunAsync.ofRun (
            let header =
              let pkg = info.sandbox.root in
              Format.asprintf
                "# Command environment for %s@%a"
                pkg.name Version.pp pkg.version
            in
            Environment.renderToShellSource ~header info.commandEnv
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
        else
          return ()
      in

      return ()

    in Perf.measureLwt ~label:"writing sandbox info cache" f

  let readCache ~(cfg : Config.t) spec =
    let open RunAsync.Syntax in
    let f () =
      let cachePath = cachePath cfg spec in
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
              List.map ~f info.info
            )
          in
          return (List.exists ~f:(fun x -> x) checks)
        in
        if isStale
        then return None
        else return (Some info)
      in
      try%lwt Lwt_io.with_file ~mode:Lwt_io.Input (Path.show cachePath) f
      with | Unix.Unix_error _ -> return None
    in Perf.measureLwt ~label:"reading sandbox info cache" f

  let make {CommonOptions. spec; cfg; _} =
    let open RunAsync.Syntax in
    let makeInfo () =
      let f () =
        let%bind sandbox, info = Sandbox.make ~cfg spec in
        let%bind () = Sandbox.init sandbox in
        let%bind task, commandEnv, sandboxEnv = RunAsync.ofRun (
          let open Run.Syntax in
          let%bind task = Task.ofSandbox sandbox in
          let%bind commandEnv =
            let%bind env = Task.commandEnv task in
            return (Sandbox.Environment.Bindings.render sandbox.buildConfig env)
          in
          let%bind sandboxEnv =
            let%bind env = Task.sandboxEnv task in
            return (Sandbox.Environment.Bindings.render sandbox.buildConfig env)
          in
          return (task, commandEnv, sandboxEnv)
        ) in
        return {spec; task; sandbox; commandEnv; sandboxEnv; info}
      in Perf.measureLwt ~label:"constructing sandbox info" f
    in
    match%bind readCache ~cfg spec with
    | Some info ->
      let%bind () = Sandbox.init info.sandbox in
      return info
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

  let resolvePackage ~pkgName ~sandbox info =
    let open RunAsync.Syntax in
    match findTaskByName ~pkgName info.task
    with
    | None -> errorf "package %s isn't built yet, run 'esy build'" pkgName
    | Some task ->
      let installPath = Sandbox.Path.toPath sandbox.Sandbox.buildConfig (Task.installPath task) in
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

  let libraries ~sandbox ~ocamlfind ?builtIns ?task () =
    let open RunAsync.Syntax in
    let ocamlpath =
      match task with
      | Some task ->
        Sandbox.Path.(Task.installPath task / "lib")
        |> Sandbox.Path.toPath sandbox.Sandbox.buildConfig
        |> Path.show
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

    let query ~sandbox ~ocamlfind ~task lib =
      let open RunAsync.Syntax in
      let ocamlpath =
        Sandbox.Path.(Task.installPath task / "lib")
        |> Sandbox.Path.toPath sandbox.Sandbox.buildConfig
      in
      let env =
        `CustomEnv Astring.String.Map.(
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

let pkgPathTerm =
  let open Cmdliner in
  let doc = "Path to package." in
  Arg.(
    value
    & pos 0  (some resolvedPathTerm) None
    & info [] ~doc
  )

let withBuildTaskByPath
    ~(info : SandboxInfo.t)
    packagePath
    f =
  let open RunAsync.Syntax in
  match packagePath with
  | Some packagePath ->
    let packagePath = Path.remEmptySeg packagePath in
    let findByPath (task : Task.t) =
      let pkg = Task.pkg task in
      Path.Set.mem packagePath pkg.originPath
      || String.equal (Path.show packagePath) pkg.id
    in
    begin match Task.Graph.find ~f:findByPath info.task with
    | None -> errorf "No package found at %a" Path.pp packagePath
    | Some pkg -> f pkg
    end
  | None -> f info.task

let buildPlan copts packagePath () =
  let open RunAsync.Syntax in

  let%bind info = SandboxInfo.make copts in

  let f task =
    let json = EsyBuildPackage.Plan.to_yojson (Task.plan task) in
    let data = Yojson.Safe.pretty_to_string json in
    print_endline data;
    return ()
  in
  withBuildTaskByPath ~info packagePath f

let buildShell copts packagePath () =
  let open RunAsync.Syntax in

  let%bind (info : SandboxInfo.t) = SandboxInfo.make copts in

  let f task =
    let%bind () =
      Build.buildDependencies
        ~concurrency:EsyRuntime.concurrency
        info.sandbox
        task
    in
    let p =
      PackageBuilder.buildShell
        ~buildConfig:info.sandbox.buildConfig
        (Task.plan task)
    in
    match%bind p with
    | Unix.WEXITED 0 -> return ()
    | Unix.WEXITED n
    | Unix.WSTOPPED n
    | Unix.WSIGNALED n -> exit n
  in withBuildTaskByPath ~info packagePath f

let buildPackage copts packagePath () =
  let open RunAsync.Syntax in

  let%bind (info : SandboxInfo.t) = SandboxInfo.make copts in

  let f task =
    Build.buildAll
      ~concurrency:EsyRuntime.concurrency
      ~force:`ForRoot
      info.sandbox
      task
  in
  withBuildTaskByPath ~info packagePath f

let build ?(buildOnly=true) copts cmd () =
  let open RunAsync.Syntax in
  let%bind {SandboxInfo. task; sandbox; _} = SandboxInfo.make copts in

  (** TODO: figure out API to build devDeps in parallel with the root *)

  match cmd with
  | None ->
    let%bind () =
      Build.buildDependencies
        ~concurrency:EsyRuntime.concurrency
        ~force:`ForRoot
        sandbox
        task
    in
    Build.buildTask ~force:true ~quiet:true ~buildOnly sandbox task

  | Some cmd ->
    let%bind () =
      Build.buildDependencies
        ~concurrency:EsyRuntime.concurrency
        sandbox
        task
    in
    let p =
      PackageBuilder.buildExec
        ~buildConfig:sandbox.buildConfig
        (Task.plan task)
        cmd
    in
    match%bind p with
    | Unix.WEXITED 0 -> return ()
    | Unix.WEXITED n
    | Unix.WSTOPPED n
    | Unix.WSIGNALED n -> exit n

let makeEnvCommand ~computeEnv ~header copts asJson packagePath () =
  let open RunAsync.Syntax in

  let%bind info = SandboxInfo.make copts in

  let f (task : Task.t) =
    let%bind source = RunAsync.ofRun (
      let open Run.Syntax in
      let%bind env = computeEnv info task in
      let pkg = Task.pkg task in
      let header = header pkg in
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
  in withBuildTaskByPath ~info packagePath f

let buildEnv =
  let open Run.Syntax in
  let header (pkg : Sandbox.Package.t) =
    Format.asprintf
      "# Build environment for %s@%a"
      pkg.name Version.pp pkg.version
  in
  let computeEnv (info : SandboxInfo.t) task =
    let%bind env = Task.buildEnv task in
    let env = Sandbox.Environment.Bindings.render info.sandbox.buildConfig env in
    return env
  in
  makeEnvCommand ~computeEnv ~header

let commandEnv =
  let open Run.Syntax in
  let header (pkg : Sandbox.Package.t) =
    Format.asprintf
      "# Command environment for %s@%a"
      pkg.name Version.pp pkg.version
  in
  let computeEnv (info : SandboxInfo.t) task =
    let%bind env = Task.commandEnv task in
    let env = Sandbox.Environment.Bindings.render info.sandbox.buildConfig env in
    return (Environment.current @ env)
  in
  makeEnvCommand ~computeEnv ~header

let sandboxEnv =
  let open Run.Syntax in
  let header (pkg : Sandbox.Package.t) =
    Format.asprintf "# Sandbox environment for %s@%a" pkg.name Version.pp pkg.version
  in
  let computeEnv (info : SandboxInfo.t) task =
    let%bind env = Task.sandboxEnv task in
    let env = Sandbox.Environment.Bindings.render info.sandbox.buildConfig env in
    Ok (Environment.current @ env)
  in
  makeEnvCommand ~computeEnv ~header

let makeExecCommand
    ?(checkIfDependenciesAreBuilt=false)
    ~env
    ~sandbox
    ~info
    cmd
    ()
  =
  let open RunAsync.Syntax in
  let {SandboxInfo. task; commandEnv; sandboxEnv; _} = info in

  let%bind () =
    if checkIfDependenciesAreBuilt
    then Build.buildDependencies ~concurrency:EsyRuntime.concurrency sandbox task
    else return ()
  in

  let%bind env = RunAsync.ofStringError (
    let open Result.Syntax in
    let env = match env with
      | `CommandEnv -> commandEnv
      | `SandboxEnv -> sandboxEnv
    in
    let env = Environment.current @ env in
    let%bind env = Environment.Bindings.eval env in
    return (`CustomEnv env)
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
    let installPath =
      Sandbox.Path.toPath
        info.sandbox.buildConfig
        (Task.installPath info.SandboxInfo.task)
    in
    if%bind Fs.exists installPath then
      return ()
    else
      build ~buildOnly:false copts None ()
  in
  makeExecCommand
    ~env:`SandboxEnv
    ~sandbox:info.sandbox
    ~info
    cmd
    ()

let devExec copts cmd () =
  let open RunAsync.Syntax in
  let%bind (info : SandboxInfo.t) = SandboxInfo.make copts in
  let%bind cmd = RunAsync.ofRun (
    let open Run.Syntax in
    let tool, args = Cmd.getToolAndArgs cmd in
    let script =
      Manifest.Scripts.find
        tool
        info.SandboxInfo.sandbox.scripts
    in
    let renderCommand (cmd : Manifest.Command.t) =
      match cmd with
      | Parsed args ->
        let%bind args =
          Result.List.map
            ~f:(Task.renderExpression ~sandbox:info.sandbox ~task:info.task)
            args
        in
        return (Cmd.ofListExn args)
      | Unparsed line ->
        let%bind string = Task.renderExpression ~sandbox:info.sandbox ~task:info.task line in
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
    ~sandbox:info.sandbox
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
    ~sandbox:info.sandbox
    ~info
    (Cmd.v shell)
    ()

let makeLsCommand ~computeTermNode ~includeTransitive (info: SandboxInfo.t) =
  let open RunAsync.Syntax in

  let seen = ref StringSet.empty in

  let f ~foldDependencies _prev (task : Task.t) =
    let id = Task.id task in
    if StringSet.mem id !seen then
      return None
    else (
      seen := StringSet.add id !seen;
      let%bind children =
        if not includeTransitive && id <> (Task.id info.task) then
          return []
        else
          foldDependencies ()
          |> List.map ~f:(fun (_, v) -> v)
          |> RunAsync.List.joinAll
      in
      let children = children |> List.filterNone in
      computeTermNode task children
    )
  in
  match%bind Task.Graph.fold ~f ~init:(return None) info.task with
  | Some tree -> return (print_endline (TermTree.render tree))
  | None -> return ()

let formatPackageInfo ~built:(built : bool)  (task : Task.t) =
  let open RunAsync.Syntax in
  let pkg = Task.pkg task in
  let version = Chalk.grey ("@" ^ Version.show pkg.version) in
  let status =
    match (Task.sourceType task), built with
    | Manifest.SourceType.Immutable, true ->
      Chalk.green "[built]"
    | _, _ ->
      Chalk.blue "[build pending]"
  in
  let line = Printf.sprintf "%s%s %s" pkg.name version status in
  return line

let lsBuilds copts includeTransitive () =
  let open RunAsync.Syntax in

  let%bind (info : SandboxInfo.t) = SandboxInfo.make copts in

  let computeTermNode task children =
    let%bind built = Task.isBuilt ~sandbox:info.sandbox task in
    let%bind line = formatPackageInfo ~built task in
    return (Some (TermTree.Node { line; children; }))
  in
  makeLsCommand ~computeTermNode ~includeTransitive info

let lsLibs copts includeTransitive () =
  let open RunAsync.Syntax in

  let%bind (info : SandboxInfo.t) = SandboxInfo.make copts in

  let%bind ocamlfind =
    let%bind p = SandboxInfo.ocamlfind ~sandbox:info.sandbox info in
    return Path.(p / "bin" / "ocamlfind")
  in
  let%bind builtIns = SandboxInfo.libraries ~sandbox:info.sandbox ~ocamlfind () in

  let computeTermNode (task: Task.t) children =
    let%bind built = Task.isBuilt ~sandbox:info.sandbox task in
    let%bind line = formatPackageInfo ~built task in

    let%bind libs =
      if built then
        SandboxInfo.libraries ~sandbox:info.sandbox ~ocamlfind ~builtIns ~task ()
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

  let%bind ocamlfind =
    let%bind p = SandboxInfo.ocamlfind ~sandbox:info.sandbox info in
    return Path.(p / "bin" / "ocamlfind")
  in
  let%bind ocamlobjinfo =
    let%bind p = SandboxInfo.ocaml ~sandbox:info.sandbox info in
    return Path.(p / "bin" / "ocamlobjinfo")
  in
  let%bind builtIns = SandboxInfo.libraries ~sandbox:info.sandbox ~ocamlfind () in

  let formatLibraryModules ~task lib =
    let%bind meta = SandboxInfo.Findlib.query ~sandbox:info.sandbox ~ocamlfind ~task lib in
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

  let computeTermNode (task: Task.t) children =
    let%bind built = Task.isBuilt ~sandbox:info.sandbox task in
    let%bind line = formatPackageInfo ~built task in

    let%bind libs =
      if built then
        SandboxInfo.libraries ~sandbox:info.sandbox ~ocamlfind ~builtIns ~task ()
      else
        return []
    in

    let isNotRoot = Task.id task <> Task.id info.task in
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
    Solution.LockfileV1.toFile ~sandbox:installSandbox ~solution lockfilePath
  in
  return solution

let solve {CommonOptions. installSandbox; _} () =
  let open RunAsync.Syntax in
  let%bind _ : EsyInstall.Solution.t = getSandboxSolution installSandbox in
  return ()

let fetch {CommonOptions. installSandbox = sandbox; _} () =
  let open EsyInstall in
  let open RunAsync.Syntax in
  let lockfilePath = SandboxSpec.lockfilePath sandbox.Sandbox.spec in
  match%bind Solution.LockfileV1.ofFile ~sandbox lockfilePath with
  | Some solution -> Fetch.fetch ~sandbox solution
  | None -> error "no lockfile found, run 'esy solve' first"

let fetchPnp {CommonOptions. installSandbox = sandbox; _} () =
  let open EsyInstall in
  let open RunAsync.Syntax in
  let lockfilePath = SandboxSpec.lockfilePath sandbox.Sandbox.spec in
  match%bind Solution.LockfileV1.ofFile ~sandbox lockfilePath with
  | Some solution -> Fetch.fetchPnP ~sandbox solution
  | None -> error "no lockfile found, run 'esy solve' first"

let solveAndFetch ({CommonOptions. installSandbox = sandbox; _} as copts) () =
  let open EsyInstall in
  let open RunAsync.Syntax in
  let lockfilePath = SandboxSpec.lockfilePath sandbox.Sandbox.spec in
  match%bind Solution.LockfileV1.ofFile ~sandbox lockfilePath with
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
      let f (record : Solution.Record.t) _ map =
        StringMap.add record.name record map
      in
      Solution.fold ~f ~init:StringMap.empty solution
    in
    let addedDependencies =
      let f {Req. name; _} =
        match StringMap.find name records with
        | Some record ->
          let constr =
            match record.Solution.Record.version with
            | Version.Npm version ->
              SemverVersion.Formula.DNF.show
                (SemverVersion.caretRangeOfVersion version)
            | Version.Opam version ->
              OpamPackage.Version.to_string version
            | Version.Source _ ->
              Version.show record.Solution.Record.version
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
      | ManyOpam _ -> error aggOpamErrorMsg
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

let dependenciesForExport (task : Task.t) =
  let f deps dep = match dep with
    | Task.Dependency, depTask
    | Task.BuildTimeDependency, depTask ->
      begin match Task.sourceType depTask with
      | Manifest.SourceType.Immutable -> (depTask, dep)::deps
      | _ -> deps
      end
    | Task.DevDependency, _ -> deps
  in
  Task.dependencies task
  |> List.fold_left ~f ~init:[]
  |> List.rev

let exportBuild copts buildPath () =
  let open RunAsync.Syntax in
  let%bind () = Sandbox.initStore copts.cfg.storePath in
  let outputPrefixPath = Path.(EsyRuntime.currentWorkingDir / "_export") in
  Task.exportBuild ~outputPrefixPath ~cfg:copts.CommonOptions.cfg buildPath

let exportDependencies copts () =
  let open RunAsync.Syntax in

  let%bind {SandboxInfo. task = rootTask; sandbox; _} =
    SandboxInfo.make copts
  in

  let tasks =
    rootTask
    |> Task.Graph.traverse ~traverse:dependenciesForExport
    |> List.filter ~f:(fun (task : Task.t) -> not (Task.id task = Task.id rootTask))
  in

  let queue = LwtTaskQueue.create ~concurrency:8 () in

  let exportBuild (task : Task.t) =
    let pkg = Task.pkg task in
    let aux () =
      let%lwt () = Logs_lwt.app (fun m -> m "Exporting %s@%a" pkg.name Version.pp pkg.version) in
      let buildPath = Sandbox.Path.toPath sandbox.buildConfig (Task.installPath task) in
      if%bind Fs.exists buildPath
      then
        let outputPrefixPath = Path.(EsyRuntime.currentWorkingDir / "_export") in
        Task.exportBuild ~outputPrefixPath ~cfg:copts.CommonOptions.cfg buildPath
      else (
        errorf
          "%s@%a was not built, run 'esy build' first"
          pkg.name Version.pp pkg.version
      )
    in LwtTaskQueue.submit queue aux
  in

  tasks
  |> List.map ~f:exportBuild
  |> RunAsync.List.waitAll

let importBuild copts fromPath buildPaths () =
  let open RunAsync.Syntax in
  let%bind () = Sandbox.initStore copts.cfg.storePath in
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
  let queue = LwtTaskQueue.create ~concurrency:8 () in
  buildPaths
  |> List.map ~f:(fun path ->
      LwtTaskQueue.submit queue (fun () -> Task.importBuild copts.CommonOptions.cfg path))
  |> RunAsync.List.waitAll

let importDependencies copts fromPath () =
  let open RunAsync.Syntax in

  let%bind {SandboxInfo. task = rootTask; sandbox; _} =
    SandboxInfo.make copts
  in

  let fromPath = match fromPath with
    | Some fromPath -> fromPath
    | None -> Path.(sandbox.buildConfig.projectPath / "_export")
  in

  let pkgs =
    rootTask
    |> Task.Graph.traverse ~traverse:dependenciesForExport
    |> List.filter ~f:(fun (task : Task.t) -> not (Task.id task = Task.id rootTask))
  in

  let queue = LwtTaskQueue.create ~concurrency:16 () in

  let importBuild (task : Task.t) =
    let aux () =
      let installPath = Sandbox.Path.toPath sandbox.buildConfig (Task.installPath task) in
      if%bind Fs.exists installPath
      then return ()
      else (
        let id = Task.id task in
        let pathDir = Path.(fromPath / id) in
        let pathTgz = Path.(fromPath / (id ^ ".tar.gz")) in
        if%bind Fs.exists pathDir
        then Task.importBuild copts.CommonOptions.cfg pathDir
        else if%bind Fs.exists pathTgz
        then Task.importBuild copts.CommonOptions.cfg pathTgz
        else
          let%lwt () =
            Logs_lwt.warn(fun m -> m "no prebuilt artifact found for %s" id)
          in return ()
      )
    in LwtTaskQueue.submit queue aux
  in

  pkgs
  |> List.map ~f:importBuild
  |> RunAsync.List.waitAll

let release copts () =
  let open RunAsync.Syntax in
  let%bind info = SandboxInfo.make copts in

  let%bind outputPath =
    let outputDir = "_release" in
    let outputPath = Path.(info.sandbox.buildConfig.projectPath / outputDir) in
    let%bind () = Fs.rmPath outputPath in
    return outputPath
  in

  let%bind () = build copts None () in

  let%bind esyInstallRelease = EsyRuntime.esyInstallRelease in

  let%bind ocamlopt =
    let%bind p = SandboxInfo.ocaml ~sandbox:info.sandbox info in
    return Path.(p / "bin" / "ocamlopt")
  in

  NpmRelease.make
    ~ocamlopt
    ~esyInstallRelease
    ~outputPath
    ~concurrency:EsyRuntime.concurrency
    ~sandbox:info.SandboxInfo.sandbox

let gc (copts : CommonOptions.t) dryRun (roots : Path.t list) () =
  let open RunAsync.Syntax in

  let perform path =
    if dryRun
    then (
      print_endline (Path.show path);
      return ()
    ) else Fs.rmPath path
  in

  let%bind () =
    let%bind () = perform Path.(copts.cfg.storePath / Store.stageTree) in
    let%bind () = perform Path.(copts.cfg.storePath / Store.buildTree) in
    return ()
  in

  let%bind () =
    let%bind keep =
      let visitSandbox keep root =
        match%lwt EsyInstall.SandboxSpec.ofPath root with
        | Ok spec ->
          let%bind sandbox, _ = Sandbox.make ~cfg:copts.cfg spec in
          let%bind task = RunAsync.ofRun (Task.ofSandbox sandbox) in
          let f ~foldDependencies keep task =
            let deps = foldDependencies () in
            let f keep (_, k) = StringSet.union keep k in
            let keep = List.fold_left ~f ~init:keep deps in
            StringSet.add (Task.id task) keep
          in
          return (Task.Graph.fold ~init:keep ~f task)
        | Error err -> Lwt.return (Error err)
      in
      RunAsync.List.foldLeft ~f:visitSandbox ~init:StringSet.empty roots
    in

    let queue = LwtTaskQueue.create ~concurrency:40 () in
    let%bind buildsIds =
      Fs.listDir Path.(copts.cfg.storePath / Store.installTree)
    in
    let removeBuild buildId =
      if StringSet.mem buildId keep
      then return ()
      else LwtTaskQueue.submit
        queue
        (fun () -> perform Path.(copts.cfg.storePath / Store.installTree / buildId))
    in
    RunAsync.List.waitAll (List.map ~f:removeBuild buildsIds)
  in

  return ()

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
        $ pkgPathTerm
        $ Cli.setupLogTerm
      );

    makeCommand
      ~name:"build-shell"
      ~doc:"Enter the build shell"
      Term.(
        const buildShell
        $ commonOpts
        $ pkgPathTerm
        $ Cli.setupLogTerm
      );

    makeCommand
      ~name:"build-package"
      ~doc:"Build specified package"
      Term.(
        const buildPackage
        $ commonOpts
        $ pkgPathTerm
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
        $ pkgPathTerm
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
        $ pkgPathTerm
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
        $ pkgPathTerm
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
      ~name:"fetch-pnp"
      ~doc:"Fetch dependencies using the solution in a lockfile"
      Term.(
        const fetchPnp
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
      ~name:"gc"
      ~doc:"Perform garbage collection of unused build artifacts."
      ~header:`No
      Term.(
        const gc
        $ commonOpts
        $ Arg.(
            value
            & flag
            & info ["dry-run";] ~doc:"Only print directories to which should be removed."
          )
        $ Arg.(
            non_empty
            & (pos_all resolvedPathTerm [])
            & info [] ~docv:"ROOT" ~doc:"Project roots for which built artifacts must be kept"
          )
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

let () =

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
