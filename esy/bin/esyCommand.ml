open Esy

module SandboxSpec = EsyInstall.SandboxSpec
module Installation = EsyInstall.Installation
module Solution = EsyInstall.Solution
module SolutionLock = EsyInstall.SolutionLock
module Version = EsyInstall.Version
module PackageId = EsyInstall.PackageId
module PkgSpec = EsyInstall.PkgSpec

let planModeConv =
  let open Cmdliner in
  let parse v =
    match v with
    | "build" -> Ok BuildSandbox.BuildSpec.Build
    | "buildDev" -> Ok BuildSandbox.BuildSpec.BuildDev
    | unknown ->
      let msg = "unknown build mode '" ^ unknown ^ "', only build or buildDev is allowed" in
      Error (`Msg msg)
  in
  Arg.conv ~docv:"MODE" (parse, BuildSandbox.BuildSpec.pp_mode)

let pkgspecConv =
  let open Cmdliner in
  let parse v = Rresult.R.error_to_msg ~pp_error:Fmt.string (PkgSpec.parse v) in
  Arg.conv ~docv:"PATH" (parse, PkgSpec.pp)

let depspecConv =
  let open Cmdliner in
  let open Result.Syntax in
  let parse v =
    let lexbuf = Lexing.from_string v in
    return (DepSpecParser.start DepSpecLexer.read lexbuf)
  in
  let pp = BuildSandbox.DepSpec.pp in
  Arg.conv ~docv:"DEPSPEC" (parse, pp)

let runAsyncToCmdlinerRetResult res =
  `Ok (Lwt_main.run res)

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
    match NodeResolution.resolve req with
    | Ok path -> path
    | Error (`Msg err) -> failwith err

  module EsyPackageJson = struct
    type t = {
      version : string
    } [@@deriving of_yojson { strict = false }]

    let read () =
      let pkgJson =
        let open RunAsync.Syntax in
        let filename = resolve "../../../../package.json" in
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
  let isProject path =
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
    if%bind isProject path
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

  let solveCudfCommandArg =
    let doc = "Set command which is used for solving CUDF problems." in
    let env = Arg.env_var "ESY__SOLVE_CUDF_COMMAND" ~doc in
    Arg.(
      value
      & opt (some Cli.cmdConv) None
      & info ["solve-cudf-command"] ~env ~doc
    )

  let make
    sandboxPath 
    prefixPath
    cachePath
    cacheTarballsPath
    opamRepository
    esyOpamOverride
    npmRegistry
    solveTimeout
    skipRepositoryUpdate
    solveCudfCommand
    =
    let open RunAsync.Syntax in
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

    let%bind sandboxPath = sandboxPath in
    let%bind spec = EsyInstall.SandboxSpec.ofPath sandboxPath in

    let%bind prefixPath = match prefixPath with
      | Some prefixPath -> return (Some prefixPath)
      | None ->
        let%bind rc = EsyRc.ofPath spec.EsyInstall.SandboxSpec.path in
        return rc.EsyRc.prefixPath
    in

    let%bind esySolveCmd =
      match solveCudfCommand with
      | Some cmd -> return cmd
      | None ->
        let cmd = EsyRuntime.resolve "esy-solve-cudf/esySolveCudfCommand.exe" in
        return Cmd.(v (p cmd))
    in

    let%bind installCfg =
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
      RunAsync.ofRun (
        Config.make
          ~installCfg
          ~spec
          ~esyVersion:EsyRuntime.version
          ~prefixPath
          ()
      )
    in

    let%bind installSandbox =
      EsyInstall.Sandbox.make ~cfg:installCfg spec
    in

    return {cfg; installSandbox; spec;}

  let termResult sandboxPath =

    let parse
      prefixPath
      cachePath
      cacheTarballsPath
      opamRepository
      esyOpamOverride
      npmRegistry
      solveTimeout
      skipRepositoryUpdate
      solveCudfCommand
      =
      let copts = make
        sandboxPath
        prefixPath
        cachePath
        cacheTarballsPath
        opamRepository
        esyOpamOverride
        npmRegistry
        solveTimeout
        skipRepositoryUpdate
        solveCudfCommand
      in
      runAsyncToCmdlinerRetResult copts
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
      $ solveCudfCommandArg
    ))

  let term sandboxPath =

    let parse
      prefixPath
      cachePath
      cacheTarballsPath
      opamRepository
      esyOpamOverride
      npmRegistry
      solveTimeout
      skipRepositoryUpdate
      solveCudfCommand
      =
      let copts = make
        sandboxPath
        prefixPath
        cachePath
        cacheTarballsPath
        opamRepository
        esyOpamOverride
        npmRegistry
        solveTimeout
        skipRepositoryUpdate
        solveCudfCommand
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
      $ solveCudfCommandArg
    ))

end

module Spec = struct

  let buildspec = BuildSandbox.{
    BuildSpec.
    buildAll = Build, DepSpec.(dependencies self);
    buildLinked = Some (BuildDev, DepSpec.(dependencies self));
  }

  let execenvspec = BuildSandbox.{
    EnvSpec.
    buildIsInProgress = false;
    includeCurrentEnv = true;
    includeBuildEnv = false;
    includeNpmBin = true;
    depspec = Some DepSpec.(package self + dependencies self + devDependencies self);
  }

  let commandenvspec = BuildSandbox.{
    EnvSpec.
    buildIsInProgress = false;
    includeCurrentEnv = true;
    includeBuildEnv = true;
    includeNpmBin = true;
    depspec = Some DepSpec.(dependencies self + devDependencies self);
  }

  let buildenvspec = BuildSandbox.{
    EnvSpec.
    buildIsInProgress = true;
    includeCurrentEnv = false;
    includeBuildEnv = true;
    includeNpmBin = false;
    depspec = None;
  }
end

module SandboxInfo = struct

  type t = {
    cfg : Config.t;
    filesUsed : FileInfo.t list;
    spec: EsyInstall.SandboxSpec.t;
    solution : Solution.t option;
    installation : EsyInstall.Installation.t option;
    sandbox : BuildSandbox.t option;
    scripts : Scripts.t;
  }

  let solution info =
    match info.solution with
    | Some solution -> RunAsync.return solution
    | None -> RunAsync.errorf "no installation found, run 'esy install'"

  let plan info =
    let open RunAsync.Syntax in
    let%bind solution = solution info in
    match info.sandbox with
    | Some sandbox ->
      RunAsync.ofRun (
        let open Run.Syntax in
        let%bind plan =
          BuildSandbox.makePlan
            sandbox
            Spec.buildspec
        in
        let pkg = EsyInstall.Solution.root solution in
        let root =
          match BuildSandbox.Plan.get plan pkg.Solution.Package.id with
          | None -> failwith "missing build for the root package"
          | Some task -> task
        in
        return (root, plan)
      )
    | None -> RunAsync.errorf "no installation found, run 'esy install'"

  let installation info =
    match info.installation with
    | Some installation -> RunAsync.return installation
    | None -> RunAsync.errorf "no installation found, run 'esy install'"

  let sandbox info =
    match info.sandbox with
    | Some sandbox -> RunAsync.return sandbox
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
          let sandboxBin = SandboxSpec.binPath info.spec in
          let sandboxBinLegacyPath = Path.(
            info.spec.path
            / "node_modules"
            / ".cache"
            / "_esy"
            / "build"
            / "bin"
          ) in
          match info.sandbox, info.solution with
          | Some sandbox, Some solution ->
            let root = Solution.root solution in
            let%bind () = Fs.createDir sandboxBin in
            let%bind commandEnv = RunAsync.ofRun (
              let open Run.Syntax in
              let header = "# Command environment" in
              let%bind commandEnv = BuildSandbox.env
                Spec.commandenvspec
                Spec.buildspec
                sandbox
                root.Solution.Package.id
              in
              let commandEnv = Scope.SandboxEnvironment.Bindings.render copts.cfg.buildCfg commandEnv in
              Environment.renderToShellSource ~header commandEnv
            ) in
            let commandExec =
              "#!/bin/bash\n" ^ commandEnv ^ "\nexec \"$@\""
            in
            let%bind () =
              RunAsync.List.waitAll [
                Fs.writeFile ~data:commandEnv Path.(sandboxBin / "command-env");
                Fs.writeFile ~perm:0o755 ~data:commandExec Path.(sandboxBin / "command-exec");
              ]
            in

            if SandboxSpec.isDefault info.spec
            then
              let%bind () = Fs.createDir sandboxBinLegacyPath in
              RunAsync.List.waitAll [
                Fs.writeFile ~data:commandEnv Path.(sandboxBinLegacyPath / "command-env");
                Fs.writeFile ~perm:0o755 ~data:commandExec Path.(sandboxBinLegacyPath / "command-exec");
              ]
            else
              return ()
          | _, _ -> return ()
        else
          return ()
      in

      return ()

    in Perf.measureLwt ~label:"writing sandbox info cache" f

  let checkIsStale filesUsed =
    let open RunAsync.Syntax in
    let%bind checks =
      RunAsync.List.joinAll (
        let f prev =
          Logs_lwt.debug (fun m -> m "SandboxInfo.checkIsStale %a" Path.pp prev.FileInfo.path);%lwt
          let%bind next = FileInfo.ofPath prev.FileInfo.path in
          return (FileInfo.compare prev next <> 0)
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
          let path = EsyInstall.SandboxSpec.solutionLockPath copts.spec in
          let%bind info = FileInfo.ofPath Path.(path / "index.json") in
          let filesUsed = info::filesUsed in
          match%bind SolutionLock.ofPath ~sandbox:copts.installSandbox path with
          | Some solution ->
            return (Some solution, filesUsed)
          | None -> return (None, filesUsed)
        in

        let%bind installation, filesUsed =
          match solution with
          | None -> return (None, filesUsed)
          | Some solution ->
            let path = EsyInstall.SandboxSpec.installationPath copts.spec in
            let%bind info = FileInfo.ofPath path in
            let filesUsed = info::filesUsed in
            begin match%bind Installation.ofPath path with
            | Some installation ->
              let isActual =
                let nodes = Solution.nodes solution in
                let checkPackageIsInInstallation isActual pkg =
                  if not isActual
                  then isActual
                  else Installation.mem pkg.Solution.Package.id installation
                in
                List.fold_left ~f:checkPackageIsInInstallation ~init:true nodes
              in
              if isActual
              then return (Some installation, filesUsed)
              else return (None, filesUsed)
            | None -> return (None, filesUsed)
            end
        in

        let%bind scripts = Scripts.ofSandbox copts.spec in
        let%bind sandboxEnv = SandboxEnv.ofSandbox copts.spec in
        let%bind sandbox, filesUsed =
          match installation, solution with
          | Some installation, Some solution ->
            let%bind sandbox, filesUsedForPlan =
              BuildSandbox.make
                ~platform:System.Platform.host
                ~sandboxEnv
                copts.cfg
                solution
                installation
            in
            let%bind filesUsedForPlan = FileInfo.ofPathSet filesUsedForPlan in
            return (Some sandbox, filesUsed @ filesUsedForPlan)
          | _, None
          | None, _ -> return (None, filesUsed)
        in
        return {
          cfg = copts.cfg;
          solution;
          installation;
          sandbox;
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
    let%bind sandbox = sandbox info in
    let%bind _, plan = plan info in
    let task =
      let open Option.Syntax in
      let%bind task = BuildSandbox.Plan.getByName plan pkgName in
      return task
    in
    match task with
    | None -> errorf "package %s isn't built yet, run 'esy build'" pkgName
    | Some task ->
      if%bind BuildSandbox.isBuilt sandbox task
      then return (BuildSandbox.Task.installPath copts.CommonOptions.cfg task)
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
        Path.(BuildSandbox.Task.installPath copts.CommonOptions.cfg task / "lib" |> show)
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
        Path.(BuildSandbox.Task.installPath copts.CommonOptions.cfg task / "lib")
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

let withPackage solution pkgspec f =
  let open RunAsync.Syntax in
  let runWith v =
    match v with
    | Some task -> f task
    | None -> errorf "no package found: %a" PkgSpec.pp pkgspec
  in
  match pkgspec with
  | PkgSpec.Root -> f (Solution.root solution)
  | PkgSpec.ByName name ->
    runWith (Solution.findByName name solution)
  | PkgSpec.ByNameVersion (name, version) ->
    runWith (Solution.findByNameVersion name version solution)
  | PkgSpec.ById id ->
    runWith (Solution.get id solution)

module Status = struct

  type t = {
    isProject: bool;
    isProjectSolved : bool;
    isProjectFetched : bool;
    isProjectReadyForDev : bool;
    rootBuildPath : Path.t option;
    rootInstallPath : Path.t option;
  } [@@deriving to_yojson]

  let notASandbox = {
    isProject = false;
    isProjectSolved = false;
    isProjectFetched = false;
    isProjectReadyForDev = false;
    rootBuildPath = None;
    rootInstallPath = None;
  }
end

let status copts _asJson () =
  let open RunAsync.Syntax in
  let open Status in

  let protectRunAsync v =
    try%lwt v
    with _ -> RunAsync.error "error"
  in

  let%lwt info = protectRunAsync (
    let%bind copts = RunAsync.ofRun copts in
    let cfg = copts.CommonOptions.cfg in
    let%bind info = SandboxInfo.make copts in
    return (cfg, info)
  ) in

  let%bind status =
    match info with
    | Error _ -> return Status.notASandbox
    | Ok (cfg, info) ->
      let%lwt solution = protectRunAsync (SandboxInfo.solution info) in
      let%lwt installation = protectRunAsync (SandboxInfo.installation info) in
      let%lwt built = protectRunAsync (
        let%bind sandbox = SandboxInfo.sandbox info in
        let%bind _root, plan = SandboxInfo.plan info in
        let checkTask built task =
          if built
          then
            match Scope.sourceType task.BuildSandbox.Task.scope with
            | Immutable
            | ImmutableWithTransientDependencies -> BuildSandbox.isBuilt sandbox task
            | Transient -> return built
          else
            return built
        in
        RunAsync.List.foldLeft
          ~f:checkTask
          ~init:true
          (BuildSandbox.Plan.all plan)
      ) in
      let%lwt rootBuildPath = protectRunAsync (
        let%bind root, _plan = SandboxInfo.plan info in
        return (Some (BuildSandbox.Task.buildPath cfg root))
      ) in
      let%lwt rootInstallPath = protectRunAsync (
        let%bind root, _plan = SandboxInfo.plan info in
        return (Some (BuildSandbox.Task.installPath cfg root))
      ) in
      return {
        isProject = true;
        isProjectSolved = Result.isOk solution;
        isProjectFetched = Result.isOk installation;
        isProjectReadyForDev = Result.getOr false built;
        rootBuildPath = Result.getOr None rootBuildPath;
        rootInstallPath = Result.getOr None rootInstallPath;
      }
  in
  Format.fprintf
    Format.std_formatter
    "%a@."
    (Json.Print.pp ~ppListBox:Fmt.vbox ~ppAssocBox:Fmt.vbox)
    (Status.to_yojson status);
  return ()

let buildPlan copts mode pkgspec () =
  let open RunAsync.Syntax in


  let%bind info = SandboxInfo.make copts in
  let%bind solution = SandboxInfo.solution info in

  let buildspec = {
    Spec.buildspec with
    buildLinked =
      let defaultMode, depspec = Spec.buildspec.buildAll in
      let mode = Option.orDefault ~default:defaultMode mode in
      Some (mode, depspec)
  } in

  let f (pkg : Solution.Package.t) =
    let%bind sandbox = SandboxInfo.sandbox info in
    let%bind plan = RunAsync.ofRun (BuildSandbox.makePlan sandbox buildspec) in
    match BuildSandbox.Plan.get plan pkg.id with
    | Some task ->
      let json = BuildSandbox.Task.to_yojson task in
      let data = Yojson.Safe.pretty_to_string json in
      print_endline data;
      return ()
    | None -> errorf "not build defined for %a" PkgSpec.pp pkgspec
  in
  withPackage solution pkgspec f

let buildShell (copts : CommonOptions.t) pkgspec () =
  let open RunAsync.Syntax in

  let%bind info = SandboxInfo.make copts in
  let%bind solution = SandboxInfo.solution info in

  let f (pkg : Solution.Package.t) =
    let%bind sandbox = SandboxInfo.sandbox info in
    let%bind plan = RunAsync.ofRun (
      BuildSandbox.makePlan
        sandbox
        Spec.buildspec
    ) in
    let%bind () =
      BuildSandbox.buildDependencies
        ~buildLinked:true
        ~concurrency:EsyRuntime.concurrency
        sandbox
        plan
        pkg.id
    in
    let p =
      BuildSandbox.buildShell
        Spec.buildspec
        sandbox
        pkg.id
    in
    match%bind p with
    | Unix.WEXITED 0 -> return ()
    | Unix.WEXITED n
    | Unix.WSTOPPED n
    | Unix.WSIGNALED n -> exit n
  in
  withPackage solution pkgspec f

let buildPackage (copts : CommonOptions.t) pkg () =
  let open RunAsync.Syntax in

  let%bind info = SandboxInfo.make copts in
  let%bind solution = SandboxInfo.solution info in

  let f (pkg : Solution.Package.t) =
    let%bind sandbox = SandboxInfo.sandbox info in
    let%bind _, plan = SandboxInfo.plan info in
    let%bind () =
      BuildSandbox.buildDependencies
        ~concurrency:EsyRuntime.concurrency
        ~buildLinked:true
        sandbox
        plan
        pkg.id
    in
    BuildSandbox.build
      ~force:true
      sandbox
      plan
      pkg.id
  in
  withPackage solution pkg f

let buildBy (copts : CommonOptions.t) release depspec pkg () =
  let open RunAsync.Syntax in
  let%bind info = SandboxInfo.make copts in
  let%bind solution = SandboxInfo.solution info in
  let mode =
    if release
    then BuildSandbox.BuildSpec.Build
    else BuildSandbox.BuildSpec.BuildDev
  in
  let buildspec =
    let depspec =
      match depspec with
      | Some depspec -> depspec
      | None -> let _mode, depspec = Spec.buildspec.buildAll in depspec
    in
    {Spec.buildspec with buildLinked = Some (mode, depspec)}
  in

  let f (pkg : Solution.Package.t) =
    Logs_lwt.app (fun m -> m "mode: %a" BuildSandbox.BuildSpec.pp_mode mode);%lwt
    let%bind sandbox = SandboxInfo.sandbox info in
    let%bind plan = RunAsync.ofRun (
      BuildSandbox.makePlan
        sandbox
        buildspec
    ) in
    let%bind () =
      BuildSandbox.buildDependencies
        ~concurrency:EsyRuntime.concurrency
        ~buildLinked:true
        sandbox
        plan
        pkg.id
    in
    BuildSandbox.build
      ~force:true
      sandbox
      plan
      pkg.id
  in
  withPackage solution pkg f

let build ?(buildOnly=true) (copts : CommonOptions.t) cmd () =
  let open RunAsync.Syntax in
  let%bind info = SandboxInfo.make copts in
  let%bind sandbox = SandboxInfo.sandbox info in
  let%bind _, plan = SandboxInfo.plan info in
  let%bind solution = SandboxInfo.solution info in
  let root = (Solution.root solution).id in
  let%bind () =
    BuildSandbox.buildDependencies
      ~buildLinked:true
      ~concurrency:EsyRuntime.concurrency
      sandbox
      plan
      root
  in
  begin match cmd with
  | None ->
    BuildSandbox.buildRoot
      ~quiet:true
      ~buildOnly
      sandbox
      plan
  | Some cmd ->
    begin match BuildSandbox.Plan.get plan root with
    | None -> return ()
    | Some task ->
      let p =
        BuildSandbox.exec
          Spec.buildenvspec
          Spec.buildspec
          sandbox
          task.pkg.id
          cmd
      in
      match%bind p with
      | Unix.WEXITED 0 -> return ()
      | Unix.WEXITED n
      | Unix.WSTOPPED n
      | Unix.WSIGNALED n -> exit n
    end
  end

let buildDependencies (copts : CommonOptions.t) all () =
  let open RunAsync.Syntax in
  let%bind info = SandboxInfo.make copts in
  let%bind sandbox = SandboxInfo.sandbox info in
  let%bind root, plan = SandboxInfo.plan info in
  BuildSandbox.buildDependencies
    ~buildLinked:all
    ~concurrency:EsyRuntime.concurrency
    sandbox
    plan
    root.BuildSandbox.Task.pkg.id

let makeEnvCommand
  ?(name="Environment")
  envspec
  buildspec
  copts
  asJson
  pkg
  ()
  =
  let open RunAsync.Syntax in

  let%bind info = SandboxInfo.make copts in
  let%bind solution = SandboxInfo.solution info in
  let%bind sandbox = SandboxInfo.sandbox info in

  let f (pkg : Solution.Package.t) =
    let%bind source = RunAsync.ofRun (
      let open Run.Syntax in
      let%bind env = BuildSandbox.env envspec buildspec sandbox pkg.id in
      let env = Scope.SandboxEnvironment.Bindings.render copts.CommonOptions.cfg.buildCfg env in
      if asJson
      then
        let%bind env = Run.ofStringError (Environment.Bindings.eval env) in
        Ok (
          env
          |> Environment.to_yojson
          |> Yojson.Safe.pretty_to_string)
      else
        let _mode, depspec = BuildSandbox.BuildSpec.classify buildspec pkg in
        let header =
          Format.asprintf {|# %s
# package:            %a
# depspec:            %a
# envspec:            %a
# buildIsInProgress:  %b
# includeBuildEnv:    %b
# includeCurrentEnv:  %b
# includeNpmBin:      %b
|}
            name
            Solution.Package.pp pkg
            BuildSandbox.DepSpec.pp depspec
            (Fmt.option BuildSandbox.DepSpec.pp) envspec.BuildSandbox.EnvSpec.depspec
            envspec.buildIsInProgress
            envspec.includeBuildEnv
            envspec.includeCurrentEnv
            envspec.includeNpmBin
        in
        Environment.renderToShellSource
          ~header
          env
    )
    in
    let%lwt () = Lwt_io.print source in
    return ()
  in
  withPackage solution pkg f

let envBy copts asJson includeBuildEnv includeCurrentEnv includeNpmBin depspec envspec pkgspec () =
  let envspec = {
    BuildSandbox.EnvSpec.
    buildIsInProgress = false;
    includeBuildEnv;
    includeCurrentEnv;
    includeNpmBin;
    depspec = envspec;
  } in
  let buildspec =
    match depspec with
    | Some depspec ->
      {Spec.buildspec with buildLinked = Some (BuildDev, depspec);}
    | None -> Spec.buildspec
  in
  makeEnvCommand
    envspec
    buildspec
    copts
    asJson
    pkgspec
    ()

let buildEnv copts asJson packagePath () =
  makeEnvCommand
    ~name:"Build environment"
    Spec.buildenvspec
    Spec.buildspec
    copts
    asJson
    packagePath
    ()

let commandEnv copts asJson packagePath () =
  makeEnvCommand
    ~name:"Command environment"
    Spec.commandenvspec
    Spec.buildspec
    copts
    asJson
    packagePath
    ()

let execEnv copts asJson packagePath () =
  makeEnvCommand
    ~name:"Exec environment"
    Spec.execenvspec
    Spec.buildspec
    copts
    asJson
    packagePath
    ()

let makeExecCommand
    ~checkIfDependenciesAreBuilt
    ~buildLinked
    envspec
    buildspec
    copts
    pkg
    cmd
    ()
  =
  let open RunAsync.Syntax in

  let%bind info = SandboxInfo.make copts in
  let%bind solution = SandboxInfo.solution info in
  let%bind sandbox = SandboxInfo.sandbox info in

  let f (pkg : Solution.Package.t) =
    let%bind plan = RunAsync.ofRun (
      BuildSandbox.makePlan
        sandbox
        buildspec
    ) in

    let%bind () =
      if checkIfDependenciesAreBuilt
      then
        BuildSandbox.buildDependencies
          ~buildLinked
          ~concurrency:EsyRuntime.concurrency
          sandbox
          plan
          pkg.id
      else return ()
    in

    let%bind status =
      BuildSandbox.exec
        envspec
        buildspec
        sandbox
        pkg.id
        cmd
    in
    match status with
    | Unix.WEXITED n
    | Unix.WSTOPPED n
    | Unix.WSIGNALED n -> exit n
  in
  withPackage solution pkg f

let execBy
  copts
  buildIsInProgress
  includeBuildEnv
  includeCurrentEnv
  includeNpmBin
  depspec
  envspec
  pkgspec
  cmd
  () =
  let envspec = {
    BuildSandbox.EnvSpec.
    buildIsInProgress;
    includeBuildEnv;
    includeCurrentEnv;
    includeNpmBin;
    depspec = envspec;
  } in
  let buildspec =
    match depspec with
    | Some depspec -> {Spec.buildspec with buildLinked = Some (BuildDev, depspec);}
    | None -> Spec.buildspec
  in
  makeExecCommand
    ~checkIfDependenciesAreBuilt:false (* not needed as we build an entire sandbox above *)
    ~buildLinked:false
    envspec
    buildspec
    copts
    pkgspec
    cmd
    ()

let exec (copts : CommonOptions.t) cmd () =
  let open RunAsync.Syntax in
  let%bind () = build ~buildOnly:false copts None () in
  makeExecCommand
    ~checkIfDependenciesAreBuilt:false (* not needed as we build an entire sandbox above *)
    ~buildLinked:false
    Spec.execenvspec
    Spec.buildspec
    copts
    PkgSpec.Root
    cmd
    ()

let runScript copts script args () =
  let open RunAsync.Syntax in
  let%bind (info : SandboxInfo.t) = SandboxInfo.make copts in
  let%bind sandbox = SandboxInfo.sandbox info in
  let%bind root, _plan = SandboxInfo.plan info in

  let scriptArgs, envspec =

    let peekArgs = function
      | ("esy"::"x"::args) ->
        "x"::args, Spec.execenvspec
      | ("esy"::"b"::args)
      | ("esy"::"build"::args) ->
        "build"::args, Spec.buildenvspec
      | ("esy"::args) ->
        args, Spec.commandenvspec
      | args ->
        args, Spec.commandenvspec
    in

    match script.Scripts.command with
    | BuildManifest.Command.Parsed args ->
      let args, spec = peekArgs args in
      BuildManifest.Command.Parsed args, spec
    | BuildManifest.Command.Unparsed line ->
      let args, spec = peekArgs (Astring.String.cuts ~sep:" " line) in
      BuildManifest.Command.Unparsed (String.concat " " args), spec
  in

  let%bind cmd = RunAsync.ofRun (
    let open Run.Syntax in

    let id = root.BuildSandbox.Task.pkg.id in
    let%bind env, scope = BuildSandbox.configure envspec Spec.buildspec sandbox id in
    let%bind env = Run.ofStringError (Scope.SandboxEnvironment.Bindings.eval env) in

    let expand v =
      let%bind v = Scope.render ~env ~buildIsInProgress:envspec.buildIsInProgress scope v in
      return (Scope.SandboxValue.render copts.CommonOptions.cfg.buildCfg v)
    in

    let%bind scriptArgs =
      match scriptArgs with
      | BuildManifest.Command.Parsed args -> Result.List.map ~f:expand args
      | BuildManifest.Command.Unparsed line ->
        let%bind line = expand line in
        ShellSplit.split line
    in

    let%bind args = Result.List.map ~f:expand args in

    return Cmd.(
      v (p EsyRuntime.currentExecutable)
      |> addArgs scriptArgs
      |> addArgs args
    )
  ) in

  let tool, line = Cmd.getToolAndLine cmd in
  Unix.execv tool line

let devExec (copts : CommonOptions.t) cmd () =
  let open RunAsync.Syntax in
  let%bind (info : SandboxInfo.t) = SandboxInfo.make copts in
  match Scripts.find (Cmd.getTool cmd) info.scripts with
  | Some script ->
    runScript copts script (Cmd.getArgs cmd) ()
  | None ->
    makeExecCommand
      ~checkIfDependenciesAreBuilt:true
      ~buildLinked:false
      Spec.commandenvspec
      Spec.buildspec
      copts
      PkgSpec.Root
      cmd
      ()

let devShell copts () =
  let shell =
    try Sys.getenv "SHELL"
    with Not_found -> "/bin/bash"
  in
  makeExecCommand
    ~checkIfDependenciesAreBuilt:true
    ~buildLinked:false
    Spec.commandenvspec
    Spec.buildspec
    copts
    PkgSpec.Root
    (Cmd.v shell)
    ()

let makeLsCommand ~computeTermNode ~includeTransitive (info: SandboxInfo.t) =
  let open RunAsync.Syntax in

  let%bind _, plan = SandboxInfo.plan info in
  let%bind solution = SandboxInfo.solution info in
  let seen = ref PackageId.Set.empty in
  let root = Solution.root solution in

  let rec draw pkg =
    let id = pkg.Solution.Package.id in
    if PackageId.Set.mem id !seen then
      return None
    else (
      let isRoot = Solution.isRoot pkg solution in
      seen := PackageId.Set.add id !seen;
      match BuildSandbox.Plan.get plan id with
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

let formatPackageInfo ~built:(built : bool)  (task : BuildSandbox.Task.t) =
  let open RunAsync.Syntax in
  let version = Chalk.grey ("@" ^ Version.show (Scope.version task.scope)) in
  let status =
    match Scope.sourceType task.scope, built with
    | BuildManifest.SourceType.Immutable, true ->
      Chalk.green "[built]"
    | _, _ ->
      Chalk.blue "[build pending]"
  in
  let line = Printf.sprintf "%s%s %s" (Scope.name task.scope) version status in
  return line

let lsBuilds (copts : CommonOptions.t) includeTransitive () =
  let open RunAsync.Syntax in

  let%bind (info : SandboxInfo.t) = SandboxInfo.make copts in
  let%bind sandbox = SandboxInfo.sandbox info in

  let computeTermNode task children =
    let%bind built = BuildSandbox.isBuilt sandbox task in
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
  let%bind sandbox = SandboxInfo.sandbox info in

  let computeTermNode (task: BuildSandbox.Task.t) children =
    let%bind built = BuildSandbox.isBuilt sandbox task in
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
  let%bind sandbox = SandboxInfo.sandbox info in
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

  let computeTermNode (task: BuildSandbox.Task.t) children =
    let%bind built = BuildSandbox.isBuilt sandbox task in
    let%bind line = formatPackageInfo ~built task in

    let%bind libs =
      if built then
        SandboxInfo.libraries ~ocamlfind ~builtIns ~task copts
      else
        return []
    in

    let isNotRoot = PackageId.compare task.pkg.id root.id <> 0 in
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
  let lockPath = SandboxSpec.solutionLockPath installSandbox.Sandbox.spec in
  let%bind () =
    SolutionLock.toPath ~sandbox:installSandbox ~solution lockPath
  in
  let unused = Resolver.getUnusedResolutions installSandbox.resolver in
  let%lwt () =
    let log resolution =
      Logs_lwt.warn (
        fun m ->
          m "resolution %a is unused (defined in %a)"
          Fmt.(quote string)
          resolution
          ManifestSpec.pp
          installSandbox.spec.manifest
      )
    in
    Lwt_list.iter_s log unused
  in
  return solution

let solve {CommonOptions. installSandbox; _} () =
  let open EsyInstall in
  let open RunAsync.Syntax in
  let%bind _ : Solution.t = getSandboxSolution installSandbox in
  return ()

let fetch {CommonOptions. installSandbox = sandbox; _} () =
  let open EsyInstall in
  let open RunAsync.Syntax in
  let lockPath = SandboxSpec.solutionLockPath sandbox.Sandbox.spec in
  match%bind SolutionLock.ofPath ~sandbox lockPath with
  | Some solution -> Fetch.fetch sandbox solution
  | None -> error "no lock found, run 'esy solve' first"

let solveAndFetch ({CommonOptions. installSandbox = sandbox; _} as copts) () =
  let open EsyInstall in
  let open RunAsync.Syntax in
  let lockPath = SandboxSpec.solutionLockPath sandbox.Sandbox.spec in
  match%bind SolutionLock.ofPath ~sandbox lockPath with
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
  let opamError =
    "add dependencies manually when working with opam sandboxes"
  in

  let%bind reqs = RunAsync.ofStringError (
    Result.List.map ~f:Req.parse reqs
  ) in

  let%bind installSandbox =
    let addReqs origDeps =
      let open Package.Dependencies in
      match origDeps with
      | NpmFormula prevReqs -> return (NpmFormula (reqs @ prevReqs))
      | OpamFormula _ -> error opamError
    in
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
      | One (Opam, _) -> error opamError
      | ManyOpam -> error opamError
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

      let%bind () =
        let%bind installSandbox =
          EsyInstall.Sandbox.make
            ~cfg:installSandbox.cfg
            installSandbox.spec
        in
        (* we can only do this because we keep invariant that the constraint we
         * save in manifest covers the installed version *)
        SolutionLock.unsafeUpdateChecksum
          ~sandbox:installSandbox
          (SandboxSpec.solutionLockPath installSandbox.spec)
      in
      return ()

let exportBuild (copts : CommonOptions.t) buildPath () =
  let outputPrefixPath = Path.(EsyRuntime.currentWorkingDir / "_export") in
  BuildSandbox.exportBuild ~outputPrefixPath ~cfg:copts.cfg buildPath

let exportDependencies (copts : CommonOptions.t) () =
  let open RunAsync.Syntax in

  let%bind info = SandboxInfo.make copts in
  let%bind _, plan = SandboxInfo.plan info in
  let%bind solution = SandboxInfo.solution info in

  let exportBuild (_, pkg) =
    match BuildSandbox.Plan.get plan pkg.Solution.Package.id with
    | None -> return ()
    | Some task ->
      let%lwt () = Logs_lwt.app (fun m -> m "Exporting %s@%a" pkg.name Version.pp pkg.version) in
      let buildPath = BuildSandbox.Task.installPath copts.CommonOptions.cfg task in
      if%bind Fs.exists buildPath
      then
        let outputPrefixPath = Path.(EsyRuntime.currentWorkingDir / "_export") in
        BuildSandbox.exportBuild ~outputPrefixPath ~cfg:copts.cfg buildPath
      else (
        errorf
          "%s@%a was not built, run 'esy build' first"
          pkg.name Version.pp pkg.version
      )
  in

  RunAsync.List.mapAndWait
    ~concurrency:8
    ~f:exportBuild
    (Solution.allDependenciesBFS (Solution.root solution).id solution)

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
    ~f:(fun path -> BuildSandbox.importBuild ~cfg:copts.cfg path)
    buildPaths

let importDependencies (copts : CommonOptions.t) fromPath () =
  let open RunAsync.Syntax in

  let%bind (info : SandboxInfo.t) = SandboxInfo.make copts in
  let%bind solution = SandboxInfo.solution info in
  let%bind sandbox = SandboxInfo.sandbox info in
  let%bind _, plan = SandboxInfo.plan info in

  let fromPath = match fromPath with
    | Some fromPath -> fromPath
    | None -> Path.(copts.cfg.buildCfg.projectPath / "_export")
  in

  let importBuild (_direct, pkg) =
    match BuildSandbox.Plan.get plan pkg.Solution.Package.id with
    | Some task ->
      if%bind BuildSandbox.isBuilt sandbox task
      then return ()
      else (
        let id = (Scope.id task.scope) in
        let pathDir = Path.(fromPath / id) in
        let pathTgz = Path.(fromPath / (id ^ ".tar.gz")) in
        if%bind Fs.exists pathDir
        then BuildSandbox.importBuild ~cfg:copts.cfg pathDir
        else if%bind Fs.exists pathTgz
        then BuildSandbox.importBuild ~cfg:copts.cfg pathTgz
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
    (Solution.allDependenciesBFS (Solution.root solution).id solution)

let show (copts : CommonOptions.t) _asJson req () =
  let open EsyInstall in
  let open RunAsync.Syntax in
  let%bind (req : Req.t) = RunAsync.ofStringError (Req.parse req) in
  let%bind resolver = Resolver.make ~cfg:copts.cfg.installCfg ~sandbox:copts.spec () in
  let%bind resolutions =
    RunAsync.contextf (
      Resolver.resolve ~name:req.name ~spec:req.spec resolver
    ) "resolving %a" Req.pp req
  in
  match req.spec with
  | VersionSpec.Npm [[SemverVersion.Constraint.ANY]]
  | VersionSpec.Opam [[OpamPackageVersion.Constraint.ANY]] ->
    let f (res : Package.Resolution.t) = match res.resolution with
    | Version v -> `String (Version.showSimple v)
    | _ -> failwith "unreachable"
    in
    `Assoc ["name", `String req.name; "versions", `List (List.map ~f resolutions)]
    |> Yojson.Safe.pretty_to_string
    |> print_endline;
    return ()
  | _ ->
    match resolutions with
    | [] -> errorf "No package found for %a" Req.pp req
    | resolution::_ ->
      let%bind pkg = RunAsync.contextf (
          Resolver.package ~resolution resolver
        ) "resolving metadata %a" Package.Resolution.pp resolution
      in
      let%bind pkg = RunAsync.ofStringError pkg in
      Package.to_yojson pkg
      |> Yojson.Safe.pretty_to_string
      |> print_endline;
      return ()

let release copts () =
  let open RunAsync.Syntax in
  let%bind info = SandboxInfo.make copts in
  let%bind solution = SandboxInfo.solution info in
  let%bind sandbox = SandboxInfo.sandbox info in

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

  NpmRelease.make
    ~ocamlopt
    ~outputPath
    ~concurrency:EsyRuntime.concurrency
    copts.CommonOptions.cfg
    sandbox
    (Solution.root solution)

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

    makeCommand
      ~header:`No
      ~name:"status"
      ~doc:"Print esy sandbox status"
      Term.(
        const status
        $ CommonOptions.termResult sandbox
        $ Arg.(value & flag & info ["json"] ~doc:"Format output as JSON")
        $ Cli.setupLogTerm
      );

    installCommand;
    buildCommand;

    makeCommand
      ~name:"build-by"
      ~doc:"Build by DEPSPEC"
      Term.(
        const buildBy
        $ commonOpts
        $ Arg.(
            value
            & flag
            & info ["release"] ~doc:"If we should build linked packages in release mode"
          )
        $ Arg.(
            value
            & opt (some depspecConv) None
            & info ["linked-depspec"] ~doc:"What to add to the env" ~docv:"DEPSPEC"
          )
        $ Arg.(
            value
            & pos 0 pkgspecConv Root
            & info [] ~doc:"Package to run build from" ~docv:"PACKAGE"
          )
        $ Cli.setupLogTerm
      );

    makeCommand
      ~name:"build-dependencies"
      ~doc:"Build dependencies"
      Term.(
        const buildDependencies
        $ commonOpts
        $ Arg.(value & flag & info ["all"]  ~doc:"Build all dependencies (including linked packages)")
        $ Cli.setupLogTerm
      );

    makeCommand
      ~header:`No
      ~name:"build-plan"
      ~doc:"Print build plan to stdout"
      Term.(
        const buildPlan
        $ commonOpts
        $ Arg.(
            value
            & opt (some planModeConv) None
            & info ["mode"] ~doc:"How to build: build or buildDev" ~docv:"BUILD"
          )
        $ Arg.(
            value
            & pos 0 pkgspecConv Root
            & info [] ~doc:"Package" ~docv:"PACKAGE"
          )
        $ Cli.setupLogTerm
      );

    makeCommand
      ~name:"build-shell"
      ~doc:"Enter the build shell"
      Term.(
        const buildShell
        $ commonOpts
        $ Arg.(
            value
            & pos 0 pkgspecConv Root
            & info [] ~doc:"Package" ~docv:"PACKAGE"
          )
        $ Cli.setupLogTerm
      );

    makeCommand
      ~name:"build-package"
      ~doc:"Build specified package"
      Term.(
        const buildPackage
        $ commonOpts
        $ Arg.(
            value
            & pos 0 pkgspecConv Root
            & info [] ~doc:"Package" ~docv:"PACKAGE"
          )
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
      ~name:"env-by"
      ~doc:"Produce environment by specification"
      Term.(
        const envBy
        $ commonOpts
        $ Arg.(value & flag & info ["json"]  ~doc:"Format output as JSON")
        $ Arg.(value & flag & info ["include-build-env"]  ~doc:"Include build environment")
        $ Arg.(value & flag & info ["include-current-env"]  ~doc:"Include current environment")
        $ Arg.(value & flag & info ["include-npm-bin"]  ~doc:"Include npm bin in PATH")
        $ Arg.(
            value
            & opt (some depspecConv) None
            & info ["linked-depspec"] ~doc:"Build env for linked packages" ~docv:"DEPSPEC"
          )
        $ Arg.(
            value
            & opt (some depspecConv) None
            & info ["envspec"] ~doc:"What to add to the env"
          )
        $ Arg.(
            required
            & pos 0 (some pkgspecConv) None
            & info [] ~doc:"Package to generate env at" ~docv:"PACKAGE"
          )
        $ Cli.setupLogTerm
      );

    makeCommand
      ~header:`No
      ~name:"exec-by"
      ~doc:"Produce environment by specification"
      Term.(
        const execBy
        $ commonOpts
        $ Arg.(value & flag & info ["build-context"]  ~doc:"Execute command in build context")
        $ Arg.(value & flag & info ["include-build-env"]  ~doc:"Include build environment")
        $ Arg.(value & flag & info ["include-current-env"]  ~doc:"Include current environment")
        $ Arg.(value & flag & info ["include-npm-bin"]  ~doc:"Include npm bin in PATH")
        $ Arg.(
            value
            & opt (some depspecConv) None
            & info ["linked-depspec"] ~doc:"Build env for linked packages" ~docv:"DEPSPEC"
          )
        $ Arg.(
            value
            & opt (some depspecConv) None
            & info ["envspec"] ~doc:"What to add to the env"
          )
        $ Arg.(
            required
            & pos 0 (some pkgspecConv) None
            & info [] ~doc:"Package to execute command at" ~docv:"PACKAGE"
          )
        $ Cli.cmdTerm
            ~doc:"Command to execute within the environment."
            ~docv:"COMMAND"
            (Cmdliner.Arg.pos_right 0)
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
        $ Arg.(
            value
            & pos 0 pkgspecConv Root
            & info [] ~doc:"Package" ~docv:"PACKAGE"
          )
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
        $ Arg.(
            value
            & pos 0 pkgspecConv Root
            & info [] ~doc:"Package" ~docv:"PACKAGE"
          )
        $ Cli.setupLogTerm
      );

    makeCommand
      ~header:`No
      ~name:"exec-env"
      ~doc:"Print exec environment to stdout"
      Term.(
        const execEnv
        $ commonOpts
        $ Arg.(value & flag & info ["json"]  ~doc:"Format output as JSON")
        $ Arg.(
            value
            & pos 0 pkgspecConv Root
            & info [] ~doc:"Package" ~docv:"PACKAGE"
          )
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
            (Cmdliner.Arg.pos_all)
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
      ~doc:"Solve dependencies and store the solution"
      Term.(
        const solve
        $ commonOpts
        $ Cli.setupLogTerm
      );

    makeCommand
      ~name:"fetch"
      ~doc:"Fetch dependencies using the stored solution"
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
      ~name:"show"
      ~doc:"Display information about available packages"
      ~header:`No
      Term.(
        const show
        $ commonOpts
        $ Arg.(value & flag & info ["json"] ~doc:"Format output as JSON")
        $ Arg.(
            required
            & pos 0 (some string) None
            & info [] ~docv:"PACKAGE" ~doc:"Package to display information about"
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
