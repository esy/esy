open Esy
open Cmdliner

type t = {
  mainprg : string;
  cfg : Config.t;
  installCfg : EsyInstall.Config.t;
  solveCfg : EsySolve.Config.t;
  spec : EsyInstall.SandboxSpec.t;
  installSandbox : EsySolve.Sandbox.t;
  sandbox : EsyInstall.Sandbox.t;
}

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

  let%bind solveCfg =
    EsySolve.Config.make
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

  let installCfg = solveCfg.EsySolve.Config.installCfg in

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
    EsySolve.Sandbox.make ~cfg:solveCfg spec
  in

  return {
    mainprg;
    cfg;
    solveCfg;
    installCfg;
    installSandbox;
    sandbox = {
      EsyInstall.Sandbox.
      cfg = installSandbox.cfg.installCfg;
      spec;
    };
    spec;
  }

let computeSolutionChecksum projcfg =
  let open RunAsync.Syntax in

  let sandbox = projcfg.installSandbox in

  let ppDependencies fmt deps =

    let ppOpamDependencies fmt deps =
      let ppDisj fmt disj =
        match disj with
        | [] -> Fmt.unit "true" fmt ()
        | [dep] -> EsySolve.Package.Dep.pp fmt dep
        | deps -> Fmt.pf fmt "(%a)" Fmt.(list ~sep:(unit " || ") EsySolve.Package.Dep.pp) deps
      in
      Fmt.pf fmt "@[<h>[@;%a@;]@]" Fmt.(list ~sep:(unit " && ") ppDisj) deps
    in

    let ppNpmDependencies fmt deps =
      let ppDnf ppConstr fmt f =
        let ppConj = Fmt.(list ~sep:(unit " && ") ppConstr) in
        Fmt.(list ~sep:(unit " || ") ppConj) fmt f
      in
      let ppVersionSpec fmt spec =
        match spec with
        | EsyInstall.VersionSpec.Npm f ->
          ppDnf EsyInstall.SemverVersion.Constraint.pp fmt f
        | EsyInstall.VersionSpec.NpmDistTag tag ->
          Fmt.string fmt tag
        | EsyInstall.VersionSpec.Opam f ->
          ppDnf EsyInstall.OpamPackageVersion.Constraint.pp fmt f
        | EsyInstall.VersionSpec.Source src ->
          Fmt.pf fmt "%a" EsyInstall.SourceSpec.pp src
      in
      let ppReq fmt req =
        Fmt.fmt "%s@%a" fmt req.EsyInstall.Req.name ppVersionSpec req.spec
      in
      Fmt.pf fmt "@[<hov>[@;%a@;]@]" (Fmt.list ~sep:(Fmt.unit ", ") ppReq) deps
    in

    match deps with
    | EsySolve.Package.Dependencies.OpamFormula deps -> ppOpamDependencies fmt deps
    | EsySolve.Package.Dependencies.NpmFormula deps -> ppNpmDependencies fmt deps
  in

  let showDependencies (deps : EsySolve.Package.Dependencies.t) =
    Format.asprintf "%a" ppDependencies deps
  in

  let digest =
    EsyInstall.PackageConfig.Resolutions.digest sandbox.root.resolutions
    |> Digestv.(add (string (showDependencies sandbox.root.dependencies)))
    |> Digestv.(add (string (showDependencies sandbox.root.devDependencies)))
  in

  let%bind digest =
    let f digest resolution =
      let resolution =
        match resolution.EsyInstall.PackageConfig.Resolution.resolution with
        | SourceOverride {source = EsyInstall.Source.Link _; override = _;} -> Some resolution
        | SourceOverride _ -> None
        | Version (EsyInstall.Version.Source (EsyInstall.Source.Link _)) -> Some resolution
        | Version _ -> None
      in
      match resolution with
      | None -> return digest
      | Some resolution ->
        begin match%bind EsySolve.Resolver.package ~resolution sandbox.resolver with
        | Error _ ->
          errorf "unable to read package: %a" EsyInstall.PackageConfig.Resolution.pp resolution
        | Ok pkg ->
          return Digestv.(add (string (showDependencies pkg.EsySolve.Package.dependencies)) digest)
        end
    in
    RunAsync.List.foldLeft
      ~f
      ~init:digest
      (EsyInstall.PackageConfig.Resolutions.entries sandbox.resolutions)
  in

  return (Digestv.toHex digest)

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
