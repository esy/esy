open Esy
open Cmdliner

type t = {
  mainprg : string;
  esyVersion : string;
  spec : EsyInstall.SandboxSpec.t;

  prefixPath : Path.t option;
  cachePath : Path.t option;
  cacheTarballsPath : Path.t option;
  opamRepository : EsySolve.Config.checkoutCfg option;
  esyOpamOverride : EsySolve.Config.checkoutCfg option;
  npmRegistry : string option;
  solveTimeout : float option;
  skipRepositoryUpdate : bool;
  solveCudfCommand : Cmd.t option;
} [@@deriving show, to_yojson]

let storePath cfg =
  let storePath =
    match cfg.prefixPath with
    | None -> EsyBuildPackage.Config.StorePathDefault
    | Some path -> EsyBuildPackage.Config.StorePathOfPrefix path
  in
  Run.ofBosError (EsyBuildPackage.Config.(configureStorePath storePath))

let findProjectPathFrom currentPath =
  let open Run.Syntax in
  let isProject path =
    let items = Sys.readdir (Path.show path) in
    let f name =
      match name with
      | "package.json"
      | "esy.json" -> true
      | "opam" ->
        (* opam could easily by a directory name *)
        let p = Path.(path / name) in
        not (Sys.is_directory Path.(show p))
      | name ->
        let p = Path.(path / name) in
        Path.hasExt ".opam" p && not (Sys.is_directory Path.(show p))
    in
    Array.exists f items
  in
  let rec climb path =
    if isProject path
    then return path
    else
      let parent = Path.parent path in
      if not (Path.compare path parent = 0)
      then climb (Path.parent path)
      else
        errorf
          "No esy project found (was looking from %a and up)"
          Path.ppPretty currentPath
  in
  climb currentPath

let findProjectPath projectPath =
  let open Run.Syntax in

  (* check if we can get projectPath from env *)
  let projectPath =
    match projectPath with
    | Some _ -> projectPath
    | None ->
      let open Option.Syntax in
      let%map v =
        StringMap.find_opt
          BuildSandbox.EsyIntrospectionEnv.rootPackageConfigPath
          System.Environment.current
      in
      Path.v v
  in

  let%bind projectPath =
    match projectPath with
    | Some path -> return path
    | None -> findProjectPathFrom (Path.currentPath ())
  in

  if Path.isAbs projectPath
  then return projectPath
  else return Path.(EsyRuntime.currentWorkingDir // projectPath)

let commonOptionsSection = Manpage.s_common_options

let prefixPath =
  let doc = "Specifies esy prefix path." in
  let env = Arg.env_var "ESY__PREFIX" ~doc in
  Arg.(
    value
    & opt (some Cli.pathConv) None
    & info ["prefix-path"] ~env ~docs:commonOptionsSection ~doc
  )

let opamRepositoryArg =
  let doc = "Specifies an opam repository to use." in
  let docv = "REMOTE[:LOCAL]" in
  let env = Arg.env_var "ESYI__OPAM_REPOSITORY" ~doc in
  Arg.(
    value
    & opt (some Cli.checkoutConv) None
    & (info ["opam-repository"] ~env ~doc ~docv ~docs:commonOptionsSection)
  )

let esyOpamOverrideArg =
  let doc = "Specifies an opam override repository to use." in
  let docv = "REMOTE[:LOCAL]" in
  let env = Arg.env_var "ESYI__OPAM_OVERRIDE"  ~doc in
  Arg.(
    value
    & opt (some Cli.checkoutConv) None
    & info ["opam-override-repository"] ~env ~doc ~docv ~docs:commonOptionsSection
  )

let cacheTarballsPath =
  let doc = "Specifies tarballs cache directory." in
  Arg.(
    value
    & opt (some Cli.pathConv) None
    & info ["cache-tarballs-path"] ~doc ~docs:commonOptionsSection
  )

let npmRegistryArg =
  let doc = "Specifies npm registry to use." in
  let env = Arg.env_var "NPM_CONFIG_REGISTRY" ~doc in
  Arg.(
    value
    & opt (some string) None
    & info ["npm-registry"] ~env ~doc ~docs:commonOptionsSection
  )

let solveTimeoutArg =
  let doc = "Specifies timeout for running depsolver." in
  Arg.(
    value
    & opt (some float) None
    & info ["solve-timeout"] ~doc ~docs:commonOptionsSection
  )

let skipRepositoryUpdateArg =
  let doc = "Skip updating opam-repository and esy-opam-overrides repositories." in
  Arg.(
    value
    & flag
    & info ["skip-repository-update"] ~doc ~docs:commonOptionsSection
  )

let cachePathArg =
  let doc = "Specifies cache directory.." in
  let env = Arg.env_var "ESYI__CACHE" ~doc in
  Arg.(
    value
    & opt (some Cli.pathConv) None
    & info ["cache-path"] ~env ~doc ~docs:commonOptionsSection
  )

let solveCudfCommandArg =
  let doc = "Set command which is used for solving CUDF problems." in
  let env = Arg.env_var "ESY__SOLVE_CUDF_COMMAND" ~doc in
  Arg.(
    value
    & opt (some Cli.cmdConv) None
    & info ["solve-cudf-command"] ~env ~doc ~docs:commonOptionsSection
  )

let make
  projectPath
  mainprg
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

  let%bind projectPath = RunAsync.ofRun (findProjectPath projectPath) in
  let%bind spec = EsyInstall.SandboxSpec.ofPath projectPath in

  let%bind prefixPath = match prefixPath with
    | Some prefixPath -> return (Some prefixPath)
    | None ->
      let%bind rc = EsyRc.ofPath spec.EsyInstall.SandboxSpec.path in
      return rc.EsyRc.prefixPath
  in

  return {
    mainprg;
    esyVersion = EsyRuntime.version;
    spec;
    prefixPath;
    cachePath;
    cacheTarballsPath;
    opamRepository;
    esyOpamOverride;
    npmRegistry;
    solveTimeout;
    skipRepositoryUpdate;
    solveCudfCommand;
  }

let promiseTerm projectPath =
  let parse
    mainprg
    prefixPath
    cachePath
    cacheTarballsPath
    opamRepository
    esyOpamOverride
    npmRegistry
    solveTimeout
    skipRepositoryUpdate
    solveCudfCommand () =
    make
      projectPath
      mainprg
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
  Cmdliner.Term.(
    const parse
    $ main_name
    $ prefixPath
    $ cachePathArg
    $ cacheTarballsPath
    $ opamRepositoryArg
    $ esyOpamOverrideArg
    $ npmRegistryArg
    $ solveTimeoutArg
    $ skipRepositoryUpdateArg
    $ solveCudfCommandArg
    $ Cli.setupLogTerm
  )

let term projectPath =
  Cmdliner.Term.(ret (const Cli.runAsyncToCmdlinerRet $ promiseTerm projectPath))
