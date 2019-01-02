open EsyPackageConfig
open EsyInstall
open Esy

module TermPp = struct
  let ppOption name pp fmt option =
    match option with
    | None -> Fmt.string fmt ""
    | Some v -> Fmt.pf fmt "%s %a \\@;" name pp v

  let ppFlag flag fmt enabled =
    if enabled
    then Fmt.pf fmt "%s \\@;" flag
    else Fmt.string fmt ""

  let ppEnvSpec fmt envspec =
    let {
      EnvSpec.
      augmentDeps;
      buildIsInProgress;
      includeCurrentEnv;
      includeBuildEnv;
      includeEsyIntrospectionEnv;
      includeNpmBin;
    } = envspec in
    Fmt.pf fmt
      "%a%a%a%a%a%a"
      (ppOption "--envspec" (Fmt.quote ~mark:"'" DepSpec.pp)) augmentDeps
      (ppFlag "--build-context") buildIsInProgress
      (ppFlag "--include-current-env") includeCurrentEnv
      (ppFlag "--include-npm-bin") includeNpmBin
      (ppFlag "--include-esy-introspection-env") includeEsyIntrospectionEnv
      (ppFlag "--include-build-env") includeBuildEnv

  let ppBuildSpec fmt buildspec =
    match buildspec.BuildSpec.buildDev with
    | None -> Fmt.string fmt ""
    | Some deps ->
      Fmt.pf fmt "%a" (ppOption "--link-depspec" DepSpec.pp) (Some deps)
end

let makeCachePath prefix (projcfg : ProjectConfig.t) =
  let hash = [
      Path.show projcfg.cfg.buildCfg.storePath;
      Path.show projcfg.spec.path;
      projcfg.cfg.esyVersion;
    ]
    |> String.concat "$$"
    |> Digest.string
    |> Digest.to_hex
  in
  Path.(SandboxSpec.cachePath projcfg.spec / (prefix ^ "-" ^ hash))

module type PROJECT = sig
  type t

  val make : ProjectConfig.t -> (t * FileInfo.t list) RunAsync.t
  val setProjecyConfig : ProjectConfig.t -> t -> t
  val cachePath : ProjectConfig.t -> Path.t
  val writeAuxCache : t -> unit RunAsync.t
end

module MakeProject (P : PROJECT) : sig
  val term : Fpath.t option -> P.t Cmdliner.Term.t
  val promiseTerm : Fpath.t option -> P.t RunAsync.t Cmdliner.Term.t
end = struct

  let checkStaleness files =
    let open RunAsync.Syntax in
    let files = files in
    let%bind checks = RunAsync.List.joinAll (
      let f prev =
        let%bind next = FileInfo.ofPath prev.FileInfo.path in
        let changed = FileInfo.compare prev next <> 0 in
        Logs_lwt.debug (fun m ->
          m "checkStaleness %a: %b" Path.pp prev.FileInfo.path changed
        );%lwt
        return changed
      in
      List.map ~f files
    ) in
    return (List.exists ~f:(fun x -> x) checks)

  let read' projcfg () =
    let open RunAsync.Syntax in
    let cachePath = P.cachePath projcfg in
    let f ic =
      try%lwt
        let%lwt v, files = (Lwt_io.read_value ic : (P.t * FileInfo.t list) Lwt.t) in
        let v = P.setProjecyConfig projcfg v in
        if%bind checkStaleness files
        then return None
        else return (Some v)
      with Failure _ -> return None
    in
    try%lwt Lwt_io.with_file ~mode:Lwt_io.Input (Path.show cachePath) f
    with | Unix.Unix_error _ -> return None

  let read projcfg =
    Perf.measureLwt ~label:"reading project cache" (read' projcfg)

  let write' projcfg v files () =
    let open RunAsync.Syntax in
    let cachePath = P.cachePath projcfg in
    let%bind () =
      let f oc =
        let%lwt () = Lwt_io.write_value ~flags:Marshal.[Closures] oc (v, files) in
        let%lwt () = Lwt_io.flush oc in
        return ()
      in
      let%bind () = Fs.createDir (Path.parent cachePath) in
      Lwt_io.with_file ~mode:Lwt_io.Output (Path.show cachePath) f
    in
    let%bind () = P.writeAuxCache v in
    return ()

  let write projcfg v files =
    Perf.measureLwt ~label:"writing project cache" (write' projcfg v files)

  let promiseTerm sandboxPath =
    let parse projcfg =
      let open RunAsync.Syntax in
      let%bind projcfg = projcfg in
      match%bind read projcfg with
      | Some proj -> return proj
      | None ->
        let%bind proj, files = P.make projcfg in
        let%bind () = write projcfg proj files in
        return proj
    in
    Cmdliner.Term.(const parse $ ProjectConfig.promiseTerm sandboxPath)

  let term sandboxPath =
    Cmdliner.Term.(ret (const Cli.runAsyncToCmdlinerRet $ promiseTerm sandboxPath))
end

type 'solved project = {
  projcfg : ProjectConfig.t;
  solved : 'solved Run.t;
}

and 'fetched solved = {
  solution : Solution.t;
  fetched : 'fetched Run.t;
}

and 'configured fetched = {
  installation : Installation.t;
  sandbox : BuildSandbox.t;
  configured : 'configured Run.t;
}

let solved proj = Lwt.return proj.solved

let fetched proj = Lwt.return (
  let open Result.Syntax in
  let%bind solved = proj.solved in
  solved.fetched
)

let configured proj = Lwt.return (
  let open Result.Syntax in
  let%bind solved = proj.solved in
  let%bind fetched = solved.fetched in
  fetched.configured
)

let makeProject makeSolved projcfg =
  let open RunAsync.Syntax in
  let%bind files =
    let paths = SandboxSpec.manifestPaths projcfg.spec in
    RunAsync.List.mapAndJoin ~f:FileInfo.ofPath paths
  in
  let files = ref files in
  let%lwt solved = makeSolved projcfg files in
  return ({projcfg; solved;}, !files)

let makeSolved makeFetched (projcfg : ProjectConfig.t) files =
  let open RunAsync.Syntax in
  let path = SandboxSpec.solutionLockPath projcfg.spec in
  let%bind info = FileInfo.ofPath Path.(path / "index.json") in
  files := info::!files;
  let%bind digest =
    EsySolve.Sandbox.digest
      Workflow.default.solvespec
      projcfg.solveSandbox
  in
  match%bind SolutionLock.ofPath ~digest projcfg.installSandbox path with
  | Some solution ->
    let%lwt fetched = makeFetched projcfg solution files in
    return {solution; fetched;}
  | None -> errorf "project is missing a lock, run `esy install`"

module OfPackageJson = struct
  type esy = {
    sandboxEnv : BuildEnv.t [@default BuildEnv.empty];
  } [@@deriving of_yojson { strict = false }]

  type t = {
    esy : esy [@default {sandboxEnv = BuildEnv.empty}]
  } [@@deriving of_yojson { strict = false }]

end

let readSandboxEnv spec =
  let open RunAsync.Syntax in
  match spec.EsyInstall.SandboxSpec.manifest with

  | EsyInstall.SandboxSpec.Manifest (Esy, filename) ->
    let%bind json = Fs.readJsonFile Path.(spec.path / filename) in
    let%bind pkgJson = RunAsync.ofRun (Json.parseJsonWith OfPackageJson.of_yojson json) in
    return pkgJson.OfPackageJson.esy.sandboxEnv

  | EsyInstall.SandboxSpec.Manifest (Opam, _)
  | EsyInstall.SandboxSpec.ManifestAggregate _ ->
    return BuildEnv.empty

let makeFetched makeConfigured (projcfg : ProjectConfig.t) solution files =
  let open RunAsync.Syntax in
  let path = EsyInstall.SandboxSpec.installationPath projcfg.spec in
  let%bind info = FileInfo.ofPath path in
  files := info::!files;
  match%bind Installation.ofPath path with
  | None -> errorf "project is not installed, run `esy install`"
  | Some installation ->
    let isActual =
      let nodes = Solution.nodes solution in
      let checkPackageIsInInstallation isActual pkg =
        if not isActual
        then isActual
        else (
          let check = Installation.mem pkg.Package.id installation in
          if not check
          then Logs.debug (fun m -> m "missing from installation %a" PackageId.pp pkg.Package.id);
          check
        )
      in
      List.fold_left ~f:checkPackageIsInInstallation ~init:true nodes
    in
    if isActual
    then
      let%bind sandbox =
        let%bind sandboxEnv = readSandboxEnv projcfg.spec in
        let%bind sandbox, filesUsedForPlan =
          BuildSandbox.make
            ~sandboxEnv
            projcfg.cfg
            solution
            installation
        in
        let%bind filesUsedForPlan = FileInfo.ofPathSet filesUsedForPlan in
        files := !files @ filesUsedForPlan;
        return sandbox
      in
      let%lwt configured = makeConfigured projcfg solution installation sandbox files in
      return {installation; sandbox; configured;}
    else errorf "project requires to update its installation, run `esy install`"

module WithoutWorkflow = struct

  type t = unit fetched solved project

  let makeConfigured _copts _solution _installation _sandbox _files =
    RunAsync.return ()

  let configureSolution =
    makeSolved (makeFetched makeConfigured)

  let make projcfg =
    makeProject configureSolution projcfg

  include MakeProject(struct
    type nonrec t = t
    let make = make
    let setProjecyConfig projcfg proj = {proj with projcfg;}
    let cachePath = makeCachePath "WithoutWorkflow"
    let writeAuxCache _ = RunAsync.return ()
  end)

end

module WithWorkflow = struct

  type configured = {
    workflow : Workflow.t;
    scripts : Scripts.t;
    planForDev : BuildSandbox.Plan.t;
    root : BuildSandbox.Task.t;
  }

  type t = configured fetched solved project

  let plan mode proj =
    let open RunAsync.Syntax in
    match mode with
    | BuildSpec.Build ->
      let%bind fetched = fetched proj in
      Lwt.return (
        BuildSandbox.makePlan
          Workflow.default.buildspec
          Build
          fetched.sandbox
      )
    | BuildSpec.BuildDev ->
      let%bind configured = configured proj in
      return configured.planForDev

  let makeConfigured projcfg solution _installation sandbox _files =
    let open RunAsync.Syntax in
    let workflow = Workflow.default in

    let%bind scripts = Scripts.ofSandbox projcfg.ProjectConfig.spec in

    let%bind root, planForDev = RunAsync.ofRun (
      let open Run.Syntax in
      let%bind plan =
        BuildSandbox.makePlan
          workflow.buildspec
          BuildDev
          sandbox
      in
      let pkg = EsyInstall.Solution.root solution in
      let root =
        match BuildSandbox.Plan.get plan pkg.Package.id with
        | None -> failwith "missing build for the root package"
        | Some task -> task
      in
      return (root, plan)
    ) in

    return {
      workflow;
      planForDev;
      root;
      scripts;
    }

  let make projcfg =
    makeProject (makeSolved (makeFetched makeConfigured)) projcfg

  let writeAuxCache proj =
    let open RunAsync.Syntax in
    let info =
      let%bind solved = solved proj in
      let%bind fetched = fetched proj in
      let%bind configured = configured proj in
      return (solved, fetched, configured)
    in
    match%lwt info with
    | Error _ -> return ()
    | Ok (solved, fetched, configured) ->
      let sandboxBin = SandboxSpec.binPath proj.projcfg.spec in
      let sandboxBinLegacyPath = Path.(
        proj.projcfg.spec.path
        / "node_modules"
        / ".cache"
        / "_esy"
        / "build"
        / "bin"
      ) in
      let root = Solution.root solved.solution in
      let%bind () = Fs.createDir sandboxBin in
      let%bind commandEnv = RunAsync.ofRun (
        let open Run.Syntax in
        let header = "# Command environment" in
        let%bind commandEnv =
          BuildSandbox.env
            configured.workflow.commandenvspec
            configured.workflow.buildspec
            BuildDev
            fetched.sandbox
            root.Package.id
        in
        let commandEnv = Scope.SandboxEnvironment.Bindings.render proj.projcfg.cfg.buildCfg commandEnv in
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

      let%bind () = Fs.createDir sandboxBinLegacyPath in
      RunAsync.List.waitAll [
        Fs.writeFile ~data:commandEnv Path.(sandboxBinLegacyPath / "command-env");
        Fs.writeFile ~perm:0o755 ~data:commandExec Path.(sandboxBinLegacyPath / "command-exec");
      ]

  let resolvePackage ~name (proj : t) =
    let open RunAsync.Syntax in
    let%bind solved = solved proj in
    let%bind fetched = fetched proj in
    let%bind configured = configured proj in

    match Solution.findByName name solved.solution with
    | None -> errorf "package %s is not installed as a part of the project" name
    | Some _ ->
      let%bind task, sandbox = RunAsync.ofRun (
        let open Run.Syntax in
        let task =
          let open Option.Syntax in
          let%bind task = BuildSandbox.Plan.getByName configured.planForDev name in
          return task
        in
        return (task, fetched.sandbox)
      ) in
      begin match task with
      | None -> errorf "package %s isn't built yet, run 'esy build'" name
      | Some task ->
        if%bind BuildSandbox.isBuilt sandbox task
        then return (BuildSandbox.Task.installPath proj.projcfg.ProjectConfig.cfg task)
        else errorf "package %s isn't built yet, run 'esy build'" name
      end

  let ocamlfind = resolvePackage ~name:"@opam/ocamlfind"
  let ocaml = resolvePackage ~name:"ocaml"

  include MakeProject(struct
    type nonrec t = t
    let make = make
    let setProjecyConfig projcfg proj = {proj with projcfg;}
    let cachePath = makeCachePath "WithWorkflow"
    let writeAuxCache = writeAuxCache
  end)

end

let withPackage proj (pkgArg : PkgArg.t) f =
  let open RunAsync.Syntax in
  let%bind solved = solved proj in
  let solution = solved.solution in
  let runWith pkg =
    match pkg with
    | Some pkg ->
      Logs_lwt.debug (fun m ->
        m "PkgArg %a resolves to %a" PkgArg.pp pkgArg Package.pp pkg
      );%lwt
      f pkg
    | None -> errorf "no package found: %a" PkgArg.pp pkgArg
  in
  let pkg =
    match pkgArg with
    | ByPkgSpec Root -> Some (Solution.root solution)
    | ByPkgSpec ByName name ->
      Solution.findByName name solution
    | ByPkgSpec ByNameVersion (name, version) ->
      Solution.findByNameVersion name version solution
    | ByPkgSpec ById id ->
      Solution.get id solution
    | ByPath path ->
      let root = proj.projcfg.installSandbox.spec.path in
      let path = Path.(EsyRuntime.currentWorkingDir // path) in
      let path = DistPath.ofPath (Path.tryRelativize ~root path) in
      Solution.findByPath path solution
  in
  runWith pkg

let buildDependencies
  ~buildLinked
  ~buildDevDependencies
  (proj : _ fetched solved project)
  plan
  pkg
  =
  let open RunAsync.Syntax in
  let%bind fetched = fetched proj in
  let () =
    Logs.info (fun m ->
      m "running:@[<v>@;%s build-dependencies \\@;%a%a%a%a@]"
      proj.projcfg.ProjectConfig.mainprg
      TermPp.ppBuildSpec (BuildSandbox.Plan.buildspec plan)
      TermPp.(ppFlag "--all") buildLinked
      TermPp.(ppFlag "--devDependencies") buildDevDependencies
      PackageId.pp pkg.Package.id
    )
  in
  match BuildSandbox.Plan.get plan pkg.id with
  | None -> RunAsync.return ()
  | Some task ->
    let dependencies = task.dependencies in
    let dependencies =
      if buildDevDependencies
      then
        dependencies
        @ PackageId.Set.elements pkg.devDependencies
      else dependencies
    in
    BuildSandbox.build
      ~concurrency:EsyRuntime.concurrency
      ~buildLinked
      fetched.sandbox
      plan
      dependencies

let buildPackage
  ~quiet
  ~buildOnly
  projcfg
  sandbox
  plan
  pkg
  =
  let () =
    Logs.info (fun m ->
      m "running:@[<v>@;%s build-package \\@;%a%a@]"
      projcfg.ProjectConfig.mainprg
      TermPp.ppBuildSpec (BuildSandbox.Plan.buildspec plan)
      PackageId.pp pkg.Package.id
    )
  in
  BuildSandbox.buildOnly
    ~force:true
    ~quiet
    ~buildOnly
    sandbox
    plan
    pkg.id

let printEnv
  ?(name="Environment")
  (proj : _ project)
  envspec
  buildspec
  mode
  asJson
  pkgarg
  ()
  =
  let open RunAsync.Syntax in

  let%bind _solved = solved proj in
  let%bind fetched = fetched proj in

  let f (pkg : Package.t) =

    let () =
      Logs.info (fun m ->
        m "running:@[<v>@;%s print-env \\@;%a%a@]"
        proj.projcfg.ProjectConfig.mainprg
        TermPp.ppEnvSpec envspec
        PackageId.pp pkg.Package.id
      )
    in

    let%bind source = RunAsync.ofRun (
      let open Run.Syntax in
      let%bind env, scope =
        BuildSandbox.configure
          envspec
          buildspec
          mode
          fetched.sandbox
          pkg.id
      in
      let env = Scope.SandboxEnvironment.Bindings.render proj.projcfg.ProjectConfig.cfg.buildCfg env in
      if asJson
      then
        let%bind env = Run.ofStringError (Environment.Bindings.eval env) in
        Ok (
          env
          |> Environment.to_yojson
          |> Yojson.Safe.pretty_to_string)
      else
        let mode = Scope.mode scope in
        let depspec = Scope.depspec scope in
        let header =
          Format.asprintf {|# %s
# package:            %a
# depspec:            %a
# mode:               %a
# envspec:            %a
# buildIsInProgress:  %b
# includeBuildEnv:    %b
# includeCurrentEnv:  %b
# includeNpmBin:      %b
|}
            name
            Package.pp pkg
            DepSpec.pp depspec
            BuildSpec.pp_mode mode
            (Fmt.option DepSpec.pp)
            envspec.EnvSpec.augmentDeps
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
  withPackage proj pkgarg f

let execCommand
    ~checkIfDependenciesAreBuilt
    ~buildLinked
    ~buildDevDependencies
    (proj : _ project)
    envspec
    buildspec
    mode
    (pkg : Package.t)
    cmd
  =
  let open RunAsync.Syntax in

  let%bind fetched = fetched proj in

  let%bind () =
    if checkIfDependenciesAreBuilt
    then
      let%bind plan = RunAsync.ofRun (
        BuildSandbox.makePlan
          buildspec
          mode
          fetched.sandbox
      ) in
      buildDependencies
        ~buildLinked
        ~buildDevDependencies
        proj
        plan
        pkg
    else return ()
  in

  let () =
    Logs.info (fun m ->
      m "running:@[<v>@;%s exec-command \\@;%a%a%a \\@;-- %a@]"
      proj.projcfg.ProjectConfig.mainprg
      TermPp.ppBuildSpec buildspec
      TermPp.ppEnvSpec envspec
      PackageId.pp pkg.Package.id
      Cmd.pp cmd
    )
  in

  let%bind status =
    BuildSandbox.exec
      envspec
      buildspec
      mode
      fetched.sandbox
      pkg.id
      cmd
  in
  match status with
  | Unix.WEXITED n
  | Unix.WSTOPPED n
  | Unix.WSIGNALED n -> exit n

