open Esy
open Cmdliner

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

type t = {
  mainprg : string;
  cfg : Config.t;
  spec : EsyInstall.SandboxSpec.t;
  installSandbox : EsyInstall.Sandbox.t;
}

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
  sandboxPath
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

  return {mainprg; cfg; installSandbox; spec;}

let promiseTerm sandboxPath =
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
    solveCudfCommand =
    make
      sandboxPath
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
  )

let term sandboxPath =
  Cmdliner.Term.(ret (const Cli.runAsyncToCmdlinerRet $ promiseTerm sandboxPath))
