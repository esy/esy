open Esy

module SandboxSpec = EsyInstall.SandboxSpec
module Installation = EsyInstall.Installation
module Solution = EsyInstall.Solution
module SolutionLock = EsyInstall.SolutionLock
module Version = EsyInstall.Version
module PackageId = EsyInstall.PackageId
module Package = EsyInstall.Package
module PkgSpec = EsyInstall.PkgSpec

module PkgArg = struct
  type t =
    | ByPkgSpec of PkgSpec.t
    | ByPath of Path.t

  let pp fmt = function
    | ByPkgSpec spec -> PkgSpec.pp fmt spec
    | ByPath path -> Path.pp fmt path

  let parse v =
    let open Result.Syntax in
    if Sys.file_exists v && not (Sys.is_directory v)
    then return (ByPath (Path.v v))
    else
      let%map pkgspec = PkgSpec.parse v in
      ByPkgSpec pkgspec

  let root = ByPkgSpec Root

  let conv =
    let open Cmdliner in
    let parse v = Rresult.R.error_to_msg ~pp_error:Fmt.string (parse v) in
    Arg.conv ~docv:"PACKAGE" (parse, pp)
end

let splitBy line ch =
  match String.index line ch with
  | idx ->
    let key = String.sub line 0 idx in
    let pos = idx + 1 in
    let val_ = String.(trim (sub line pos (length line - pos))) in
    Some (key, val_)
  | exception Not_found -> None

let depspecConv =
  let open Cmdliner in
  let open Result.Syntax in
  let parse v =
    let lexbuf = Lexing.from_string v in
    try return (DepSpecParser.start DepSpecLexer.read lexbuf) with
    | DepSpecLexer.Error msg ->
      let msg = Printf.sprintf "error parsing DEPSPEC: %s" msg in
      error (`Msg msg)
    | DepSpecParser.Error -> error (`Msg "error parsing DEPSPEC")
  in
  let pp = DepSpec.pp in
  Arg.conv ~docv:"DEPSPEC" (parse, pp)

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
      includeNpmBin;
    } = envspec in
    Fmt.pf fmt
      "%a%a%a%a%a"
      (ppOption "--envspec" (Fmt.quote ~mark:"'" DepSpec.pp)) augmentDeps
      (ppFlag "--build-context") buildIsInProgress
      (ppFlag "--include-current-env") includeCurrentEnv
      (ppFlag "--include-npm-bin") includeNpmBin
      (ppFlag "--include-build-env") includeBuildEnv

  let ppMode fmt mode =
    match mode with
    | BuildSpec.Build -> Fmt.pf fmt "--release \\@;"
    | BuildSpec.BuildDev -> Fmt.pf fmt ""

  let ppBuildSpec fmt buildspec =
    match buildspec.BuildSpec.buildLink with
    | None -> Fmt.string fmt ""
    | Some {mode; deps} ->
      Fmt.pf fmt
        "%a%a"
        ppMode mode
        (ppOption "--link-depspec" DepSpec.pp) (Some deps)
end

let resolvePackage ~pkgName (proj : Project.WithWorkflow.t) =
  let open RunAsync.Syntax in
  let%bind fetched = Project.fetched proj in
  let%bind configured = Project.configured proj in
  let%bind task, sandbox = RunAsync.ofRun (
    let open Run.Syntax in
    let task =
      let open Option.Syntax in
      let%bind task = BuildSandbox.Plan.getByName configured.Project.WithWorkflow.plan pkgName in
      return task
    in
    return (task, fetched.Project.sandbox)
  ) in
  match task with
  | None -> errorf "package %s isn't built yet, run 'esy build'" pkgName
  | Some task ->
    if%bind BuildSandbox.isBuilt sandbox task
    then return (BuildSandbox.Task.installPath proj.projcfg.ProjectConfig.cfg task)
    else errorf "package %s isn't built yet, run 'esy build'" pkgName

let ocamlfind = resolvePackage ~pkgName:"@opam/ocamlfind"
let ocaml = resolvePackage ~pkgName:"ocaml"

module Findlib = struct
  type meta = {
    package : string;
    description : string;
    version : string;
    archive : string;
    location : string;
  }

  let query ~ocamlfind ~task projcfg lib =
    let open RunAsync.Syntax in
    let ocamlpath =
      Path.(BuildSandbox.Task.installPath projcfg.ProjectConfig.cfg task / "lib")
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

  let libraries ~ocamlfind ?builtIns ?task projcfg =
    let open RunAsync.Syntax in
    let ocamlpath =
      match task with
      | Some task ->
        Path.(BuildSandbox.Task.installPath projcfg.ProjectConfig.cfg task / "lib" |> show)
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

let withPackage proj solution (pkgArg : PkgArg.t) f =
  let open RunAsync.Syntax in
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
      let root = proj.Project.projcfg.installSandbox.spec.path in
      let path = Path.(EsyRuntime.currentWorkingDir // path) in
      let path = EsyInstall.DistPath.ofPath (Path.tryRelativize ~root path) in
      Solution.findByPath path solution
  in
  runWith pkg

let runBuildDependencies
  ~buildLinked
  ~buildDevDependencies
  (proj : _ Project.fetched Project.solved Project.project)
  plan
  pkg
  =
  let open RunAsync.Syntax in
  let%bind fetched = Project.fetched proj in
  let () =
    Logs.info (fun m ->
      m "running:@[<v>@;%s build-dependencies \\@;%a%a@]"
      proj.projcfg.ProjectConfig.mainprg
      TermPp.ppBuildSpec (BuildSandbox.Plan.buildspec plan)
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
      fetched.Project.sandbox
      plan
      dependencies

let buildDependencies (proj : Project.WithoutWorkflow.t) release all devDependencies depspec pkgspec () =
  let open RunAsync.Syntax in
  let%bind solved = Project.solved proj in
  let%bind fetched = Project.fetched proj in
  let mode =
    if release
    then BuildSpec.Build
    else BuildSpec.BuildDev
  in
  let f (pkg : Package.t) =
    let buildspec =
      let deps =
        match depspec with
        | Some depspec -> depspec
        | None -> let {BuildSpec. deps; mode = _} = Workflow.default.buildspec.build in deps
      in
      {Workflow.default.buildspec with buildLink = Some {mode; deps}}
    in
    let%bind plan = RunAsync.ofRun (
      BuildSandbox.makePlan
        fetched.Project.sandbox
        buildspec
    ) in
    runBuildDependencies
      ~buildLinked:all
      ~buildDevDependencies:devDependencies
      proj
      plan
      pkg
  in
  withPackage proj solved.Project.solution pkgspec f

let runBuild
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

let buildPackage (proj : Project.WithoutWorkflow.t) release depspec pkgspec () =
  let open RunAsync.Syntax in

  let%bind solved = Project.solved proj in
  let%bind fetched = Project.fetched proj in

  let mode =
    if release
    then BuildSpec.Build
    else BuildSpec.BuildDev
  in

  let buildspec =
    let deps =
      match depspec with
      | Some depspec -> depspec
      | None -> let {BuildSpec. deps; mode = _} = Workflow.default.buildspec.build in deps
    in
    {Workflow.default.buildspec with buildLink = Some {mode; deps}}
  in

  let f (pkg : Package.t) =
    let%bind plan = RunAsync.ofRun (
      BuildSandbox.makePlan
        fetched.Project.sandbox
        buildspec
    ) in
    runBuild
      ~quiet:true
      ~buildOnly:true
      proj.projcfg
      fetched.Project.sandbox
      plan
      pkg
  in
  withPackage proj solved.Project.solution pkgspec f

let runExec
    ~checkIfDependenciesAreBuilt
    ~buildLinked
    ~buildDevDependencies
    (proj : _ Project.project)
    envspec
    buildspec
    (pkgspec : PkgArg.t)
    cmd
    ()
  =
  let open RunAsync.Syntax in

  let%bind solved = Project.solved proj in
  let%bind fetched = Project.fetched proj in

  let f (pkg : Package.t) =

    let%bind plan = RunAsync.ofRun (
      BuildSandbox.makePlan
        fetched.Project.sandbox
        buildspec
    ) in

    let%bind () =
      if checkIfDependenciesAreBuilt
      then
        runBuildDependencies
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
        TermPp.ppBuildSpec (BuildSandbox.Plan.buildspec plan)
        TermPp.ppEnvSpec envspec
        PackageId.pp pkg.Package.id
        Cmd.pp cmd
      )
    in

    let%bind status =
      BuildSandbox.exec
        envspec
        buildspec
        fetched.Project.sandbox
        pkg.id
        cmd
    in
    match status with
    | Unix.WEXITED n
    | Unix.WSTOPPED n
    | Unix.WSIGNALED n -> exit n
  in
  withPackage proj solved.Project.solution pkgspec f

let execCommand
  (proj : _ Project.project)
  release
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
    EnvSpec.
    buildIsInProgress;
    includeBuildEnv;
    includeCurrentEnv;
    includeNpmBin;
    augmentDeps = envspec;
  } in
  let mode =
    if release
    then BuildSpec.Build
    else BuildSpec.BuildDev
  in
  let buildspec =
    match depspec with
    | Some deps -> {Workflow.default.buildspec with buildLink = Some {mode; deps};}
    | None ->
      {
        Workflow.default.buildspec
        with buildLink = Some {mode; deps = Workflow.defaultDepspecForLink};
      }
  in
  runExec
    ~checkIfDependenciesAreBuilt:false
    ~buildDevDependencies:false
    ~buildLinked:false
    proj
    envspec
    buildspec
    pkgspec
    cmd
    ()

let runPrintEnv
  ?(name="Environment")
  (proj : _ Project.project)
  envspec
  buildspec
  asJson
  pkg
  ()
  =
  let open RunAsync.Syntax in

  let%bind solved = Project.solved proj in
  let%bind fetched = Project.fetched proj in

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
      let%bind env = BuildSandbox.env envspec buildspec fetched.Project.sandbox pkg.id in
      let env = Scope.SandboxEnvironment.Bindings.render proj.projcfg.ProjectConfig.cfg.buildCfg env in
      if asJson
      then
        let%bind env = Run.ofStringError (Environment.Bindings.eval env) in
        Ok (
          env
          |> Environment.to_yojson
          |> Yojson.Safe.pretty_to_string)
      else
        let {BuildSpec.mode = _; deps} =
          BuildSpec.classify buildspec solved.Project.solution pkg
        in
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
            Package.pp pkg
            DepSpec.pp deps
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
  withPackage proj solved.Project.solution pkg f

let printEnv
  (proj : _ Project.project)
  asJson
  includeBuildEnv
  includeCurrentEnv
  includeNpmBin
  depspec
  envspec
  pkgspec
  ()
  =
  let envspec = {
    EnvSpec.
    buildIsInProgress = false;
    includeBuildEnv;
    includeCurrentEnv;
    includeNpmBin;
    augmentDeps = envspec;
  } in
  let buildspec =
    match depspec with
    | Some deps ->
      {Workflow.default.buildspec with buildLink = Some {mode = BuildDev; deps;};}
    | None -> Workflow.default.buildspec
  in
  runPrintEnv
    proj
    envspec
    buildspec
    asJson
    pkgspec
    ()

module Status = struct

  type t = {
    isProject: bool;
    isProjectSolved : bool;
    isProjectFetched : bool;
    isProjectReadyForDev : bool;
    rootBuildPath : Path.t option;
    rootInstallPath : Path.t option;
  } [@@deriving to_yojson]

  let notAProject = {
    isProject = false;
    isProjectSolved = false;
    isProjectFetched = false;
    isProjectReadyForDev = false;
    rootBuildPath = None;
    rootInstallPath = None;
  }

end

let status
  (maybeProject : Project.WithWorkflow.t RunAsync.t)
  _asJson
  ()
  =
  let open RunAsync.Syntax in
  let open Status in

  let protectRunAsync v =
    try%lwt v
    with _ -> RunAsync.error "fatal error which is ignored by status command"
  in

  let%bind status =
    match%lwt protectRunAsync maybeProject with
    | Error _ -> return notAProject
    | Ok proj ->
      let%lwt isProjectSolved =
        let%lwt solved = Project.solved proj in
        Lwt.return (Result.isOk solved)
      in
      let%lwt isProjectFetched =
        let%lwt fetched = Project.fetched proj in
        Lwt.return (Result.isOk fetched)
      in
      let%lwt built = protectRunAsync (
        let%bind fetched = Project.fetched proj in
        let%bind configured = Project.configured proj in
        let checkTask built task =
          if built
          then
            match Scope.sourceType task.BuildSandbox.Task.scope with
            | Immutable
            | ImmutableWithTransientDependencies ->
              BuildSandbox.isBuilt fetched.Project.sandbox task
            | Transient -> return built
          else
            return built
        in
        RunAsync.List.foldLeft
          ~f:checkTask
          ~init:true
          (BuildSandbox.Plan.all configured.Project.WithWorkflow.plan)
      ) in
      let%lwt rootBuildPath =
        let open RunAsync.Syntax in
        let%bind configured = Project.configured proj in
        let root = configured.Project.WithWorkflow.root in
        return (Some (BuildSandbox.Task.buildPath proj.projcfg.ProjectConfig.cfg root))
        in
      let%lwt rootInstallPath =
        let open RunAsync.Syntax in
        let%bind configured = Project.configured proj in
        let root = configured.Project.WithWorkflow.root in
        return (Some (BuildSandbox.Task.installPath proj.projcfg.ProjectConfig.cfg root))
      in
      return {
        isProject = true;
        isProjectSolved;
        isProjectFetched;
        isProjectReadyForDev = Result.getOr false built;
        rootBuildPath = Result.getOr None rootBuildPath;
        rootInstallPath = Result.getOr None rootInstallPath;
      }
    in
    Format.fprintf
      Format.std_formatter
      "%a@."
      Json.Print.ppRegular
      (Status.to_yojson status);
  return ()

let buildPlan (proj : Project.WithWorkflow.t) pkgspec () =
  let open RunAsync.Syntax in

  let%bind solved = Project.solved proj in
  let%bind configured = Project.configured proj in

  let f (pkg : Package.t) =
    match BuildSandbox.Plan.get configured.Project.WithWorkflow.plan pkg.id with
    | Some task ->
      let json = BuildSandbox.Task.to_yojson task in
      let data = Yojson.Safe.pretty_to_string json in
      print_endline data;
      return ()
    | None -> errorf "not build defined for %a" PkgArg.pp pkgspec
  in
  withPackage proj solved.Project.solution pkgspec f

let buildShell (proj : Project.WithWorkflow.t) pkgspec () =
  let open RunAsync.Syntax in

  let%bind solved = Project.solved proj in
  let%bind fetched = Project.fetched proj in
  let%bind configured = Project.configured proj in

  let f (pkg : Package.t) =
    let%bind () =
      runBuildDependencies
        ~buildLinked:true
        ~buildDevDependencies:false
        proj
        configured.Project.WithWorkflow.plan
        pkg
    in
    let p =
      BuildSandbox.buildShell
        configured.Project.WithWorkflow.workflow.buildspec
        fetched.Project.sandbox
        pkg.id
    in
    match%bind p with
    | Unix.WEXITED 0 -> return ()
    | Unix.WEXITED n
    | Unix.WSTOPPED n
    | Unix.WSIGNALED n -> exit n
  in
  withPackage proj solved.Project.solution pkgspec f

let build ?(buildOnly=true) (proj : Project.WithWorkflow.t) cmd () =
  let open RunAsync.Syntax in

  let%bind fetched = Project.fetched proj in
  let%bind configured = Project.configured proj in

  begin match cmd with
  | None ->
    let%bind () =
      runBuildDependencies
        ~buildLinked:true
        ~buildDevDependencies:true
        proj
        configured.Project.WithWorkflow.plan
        configured.Project.WithWorkflow.root.pkg
    in
    runBuild
      ~quiet:true
      ~buildOnly
      proj.projcfg
      fetched.Project.sandbox
      configured.Project.WithWorkflow.plan
      configured.Project.WithWorkflow.root.pkg
  | Some cmd ->
    let%bind () =
      runBuildDependencies
        ~buildLinked:true
        ~buildDevDependencies:true
        proj
        configured.Project.WithWorkflow.plan
        configured.Project.WithWorkflow.root.pkg
    in
    runExec
      ~checkIfDependenciesAreBuilt:false
      ~buildLinked:false
      ~buildDevDependencies:false
      proj
      configured.workflow.buildenvspec
      configured.workflow.buildspec
      PkgArg.root
      cmd
      ()
  end

let buildEnv (proj : Project.WithWorkflow.t) asJson packagePath () =
  let open RunAsync.Syntax in
  let%bind configured = Project.configured proj in
  runPrintEnv
    ~name:"Build environment"
    proj
    configured.Project.WithWorkflow.workflow.buildenvspec
    configured.Project.WithWorkflow.workflow.buildspec
    asJson
    packagePath
    ()

let commandEnv (proj : Project.WithWorkflow.t) asJson packagePath () =
  let open RunAsync.Syntax in
  let%bind configured = Project.configured proj in
  runPrintEnv
    ~name:"Command environment"
    proj
    configured.Project.WithWorkflow.workflow.commandenvspec
    configured.Project.WithWorkflow.workflow.buildspec
    asJson
    packagePath
    ()

let execEnv (proj : Project.WithWorkflow.t) asJson packagePath () =
  let open RunAsync.Syntax in
  let%bind configured = Project.configured proj in
  runPrintEnv
    ~name:"Exec environment"
    proj
    configured.Project.WithWorkflow.workflow.execenvspec
    configured.Project.WithWorkflow.workflow.buildspec
    asJson
    packagePath
    ()

let exec (proj : Project.WithWorkflow.t) cmd () =
  let open RunAsync.Syntax in
  let%bind configured = Project.configured proj in
  let%bind () = build ~buildOnly:false proj None () in
  runExec
    ~checkIfDependenciesAreBuilt:false (* not needed as we build an entire sandbox above *)
    ~buildLinked:false
    ~buildDevDependencies:false
    proj
    configured.Project.WithWorkflow.workflow.execenvspec
    configured.Project.WithWorkflow.workflow.buildspec
    PkgArg.root
    cmd
    ()

let runScript (proj : Project.WithWorkflow.t) script args () =
  let open RunAsync.Syntax in

  let%bind fetched = Project.fetched proj in
  let%bind (configured : Project.WithWorkflow.configured) = Project.configured proj in

  let scriptArgs, envspec =

    let peekArgs = function
      | ("esy"::"x"::args) ->
        "x"::args, configured.Project.WithWorkflow.workflow.execenvspec
      | ("esy"::"b"::args)
      | ("esy"::"build"::args) ->
        "build"::args, configured.workflow.buildenvspec
      | ("esy"::args) ->
        args, configured.workflow.commandenvspec
      | args ->
        args, configured.workflow.commandenvspec
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

    let id = configured.root.pkg.id in
    let%bind env, scope =
      BuildSandbox.configure
        envspec
        configured.workflow.buildspec fetched.Project.sandbox
        id
    in
    let%bind env = Run.ofStringError (Scope.SandboxEnvironment.Bindings.eval env) in

    let expand v =
      let%bind v = Scope.render ~env ~buildIsInProgress:envspec.buildIsInProgress scope v in
      return (Scope.SandboxValue.render proj.projcfg.cfg.buildCfg v)
    in

    let%bind scriptArgs =
      match scriptArgs with
      | BuildManifest.Command.Parsed args -> Result.List.map ~f:expand args
      | BuildManifest.Command.Unparsed line ->
        let%bind line = expand line in
        ShellSplit.split line
    in

    let%bind args = Result.List.map ~f:expand args in

    let cmd = Cmd.(
      v (p EsyRuntime.currentExecutable)
      |> addArgs scriptArgs
      |> addArgs args
    ) in
    return cmd
  ) in

  let%bind status =
    ChildProcess.runToStatus
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

let devExec (proj : Project.WithWorkflow.t) cmd () =
  let open RunAsync.Syntax in
  let%bind (configured : Project.WithWorkflow.configured) = Project.configured proj in
  match Scripts.find (Cmd.getTool cmd) configured.scripts with
  | Some script ->
    runScript proj script (Cmd.getArgs cmd) ()
  | None ->
    runExec
      ~checkIfDependenciesAreBuilt:true
      ~buildLinked:false
      ~buildDevDependencies:true
      proj
      configured.workflow.commandenvspec
      configured.workflow.buildspec
      PkgArg.root
      cmd
      ()

let devShell (proj : Project.WithWorkflow.t) () =
  let open RunAsync.Syntax in
  let%bind (configured : Project.WithWorkflow.configured) = Project.configured proj in
  let shell =
    try Sys.getenv "SHELL"
    with Not_found -> "/bin/bash"
  in
  runExec
    ~checkIfDependenciesAreBuilt:true
    ~buildLinked:false
    ~buildDevDependencies:true
    proj
    configured.workflow.commandenvspec
    configured.workflow.buildspec
    PkgArg.root
    (Cmd.v shell)
    ()

let makeLsCommand ~computeTermNode ~includeTransitive (proj: Project.WithWorkflow.t) =
  let open RunAsync.Syntax in

  let%bind solved = Project.solved proj in
  let%bind configured = Project.configured proj in

  let seen = ref PackageId.Set.empty in
  let root = Solution.root solved.Project.solution in

  let rec draw pkg =
    let id = pkg.Package.id in
    if PackageId.Set.mem id !seen then
      return None
    else (
      let isRoot = Solution.isRoot pkg solved.Project.solution in
      seen := PackageId.Set.add id !seen;
      match BuildSandbox.Plan.get configured.Project.WithWorkflow.plan id with
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
              Solution.dependencies ~traverse pkg solved.solution
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

let lsBuilds (proj : Project.WithWorkflow.t) includeTransitive () =
  let open RunAsync.Syntax in
  let%bind fetched = Project.fetched proj in
  let computeTermNode task children =
    let%bind built = BuildSandbox.isBuilt fetched.Project.sandbox task in
    let%bind line = formatPackageInfo ~built task in
    return (Some (TermTree.Node { line; children; }))
  in
  makeLsCommand ~computeTermNode ~includeTransitive proj

let lsLibs (proj : Project.WithWorkflow.t) includeTransitive () =
  let open RunAsync.Syntax in
  let%bind fetched = Project.fetched proj in

  let%bind ocamlfind =
    let%bind p = ocamlfind proj in
    return Path.(p / "bin" / "ocamlfind")
  in
  let%bind builtIns = Findlib.libraries ~ocamlfind proj.projcfg in

  let computeTermNode (task: BuildSandbox.Task.t) children =
    let%bind built = BuildSandbox.isBuilt fetched.Project.sandbox task in
    let%bind line = formatPackageInfo ~built task in

    let%bind libs =
      if built then
        Findlib.libraries ~ocamlfind ~builtIns ~task proj.projcfg
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
  makeLsCommand ~computeTermNode ~includeTransitive proj

let lsModules (proj : Project.WithWorkflow.t) only () =
  let open RunAsync.Syntax in

  let%bind fetched = Project.fetched proj in
  let%bind configured = Project.configured proj in

  let%bind ocamlfind =
    let%bind p = ocamlfind proj in
    return Path.(p / "bin" / "ocamlfind")
  in
  let%bind ocamlobjinfo =
    let%bind p = ocaml proj in
    return Path.(p / "bin" / "ocamlobjinfo")
  in
  let%bind builtIns = Findlib.libraries ~ocamlfind proj.projcfg in

  let formatLibraryModules ~task lib =
    let%bind meta = Findlib.query ~ocamlfind ~task proj.projcfg lib in
    let open Findlib in

    if String.length(meta.archive) == 0 then
      let description = Chalk.dim(meta.description) in
      return [TermTree.Node { line=description; children=[]; }]
    else begin
      Path.ofString (meta.location ^ Path.dirSep ^ meta.archive) |> function
      | Ok archive ->
        if%bind Fs.exists archive then begin
          let archive = Path.show archive in
          let%bind lines =
            Findlib.modules ~ocamlobjinfo archive
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
    let%bind built = BuildSandbox.isBuilt fetched.Project.sandbox task in
    let%bind line = formatPackageInfo ~built task in

    let%bind libs =
      if built then
        Findlib.libraries ~ocamlfind ~builtIns ~task proj.projcfg
      else
        return []
    in

    let isNotRoot = PackageId.compare task.pkg.id configured.Project.WithWorkflow.root.pkg.id <> 0 in
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
  makeLsCommand ~computeTermNode ~includeTransitive:false proj

let getSandboxSolution (projcfg : ProjectConfig.t) =
  let open EsySolve in
  let open RunAsync.Syntax in
  let%bind solution = Solver.solve projcfg.installSandbox in
  let lockPath = SandboxSpec.solutionLockPath projcfg.installSandbox.Sandbox.spec in
  let%bind () =
    let%bind checksum = ProjectConfig.computeSolutionChecksum projcfg in
    EsyInstall.SolutionLock.toPath ~checksum ~sandbox:projcfg.sandbox ~solution lockPath
  in
  let unused = Resolver.getUnusedResolutions projcfg.installSandbox.resolver in
  let%lwt () =
    let log resolution =
      Logs_lwt.warn (
        fun m ->
          m "resolution %a is unused (defined in %a)"
          Fmt.(quote string)
          resolution
          EsyInstall.ManifestSpec.pp
          projcfg.installSandbox.spec.manifest
      )
    in
    Lwt_list.iter_s log unused
  in
  return solution

let solve projcfg () =
  let open RunAsync.Syntax in
  let%bind _ : Solution.t = getSandboxSolution projcfg in
  return ()

let fetch (projcfg : ProjectConfig.t) () =
  let open RunAsync.Syntax in
  let lockPath = SandboxSpec.solutionLockPath projcfg.spec in
  let%bind checksum = ProjectConfig.computeSolutionChecksum projcfg in
  match%bind SolutionLock.ofPath ~checksum ~sandbox:projcfg.sandbox lockPath with
  | Some solution -> EsyInstall.Fetch.fetch projcfg.sandbox solution
  | None -> error "no lock found, run 'esy solve' first"

let solveAndFetch (projcfg : ProjectConfig.t) () =
  let open RunAsync.Syntax in
  let lockPath = SandboxSpec.solutionLockPath projcfg.spec in
  let%bind checksum = ProjectConfig.computeSolutionChecksum projcfg in
  match%bind SolutionLock.ofPath ~checksum ~sandbox:projcfg.sandbox lockPath with
  | Some solution ->
    if%bind EsyInstall.Fetch.isInstalled ~sandbox:projcfg.sandbox solution
    then return ()
    else fetch projcfg ()
  | None ->
    let%bind () = solve projcfg () in
    let%bind () = fetch projcfg () in
    return ()

let add ({ProjectConfig. installSandbox; _} as projcfg) (reqs : string list) () =
  let open EsySolve in
  let open RunAsync.Syntax in
  let opamError =
    "add dependencies manually when working with opam sandboxes"
  in

  let%bind reqs = RunAsync.ofStringError (
    Result.List.map ~f:EsyInstall.Req.parse reqs
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

  let projcfg = {projcfg with installSandbox} in

  let%bind solution = getSandboxSolution projcfg in
  let%bind () = fetch projcfg () in

  let%bind addedDependencies, configPath =
    let records =
      let f (record : EsyInstall.Package.t) _ map =
        StringMap.add record.name record map
      in
      Solution.fold ~f ~init:StringMap.empty solution
    in
    let addedDependencies =
      let f {EsyInstall.Req. name; _} =
        match StringMap.find name records with
        | Some record ->
          let constr =
            match record.EsyInstall.Package.version with
            | Version.Npm version ->
              EsyInstall.SemverVersion.Formula.DNF.show
                (EsyInstall.SemverVersion.caretRangeOfVersion version)
            | Version.Opam version ->
              OpamPackage.Version.to_string version
            | Version.Source _ ->
              Version.show record.EsyInstall.Package.version
          in
          name, `String constr
        | None -> assert false
      in
      List.map ~f reqs
    in
    let%bind path =
      let spec = projcfg.installSandbox.Sandbox.spec in
      match spec.manifest with
      | EsyInstall.ManifestSpec.One (Esy, fname) -> return Path.(spec.SandboxSpec.path / fname)
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
          EsySolve.Sandbox.make
            ~cfg:installSandbox.cfg
            installSandbox.spec
        in
        let projcfg = {projcfg with installSandbox} in
        let%bind checksum = ProjectConfig.computeSolutionChecksum projcfg in
        (* we can only do this because we keep invariant that the constraint we
         * save in manifest covers the installed version *)
        EsyInstall.SolutionLock.unsafeUpdateChecksum
          ~checksum
          (SandboxSpec.solutionLockPath installSandbox.spec)
      in
      return ()

let exportBuild (proj : Project.WithWorkflow.t) buildPath () =
  let outputPrefixPath = Path.(EsyRuntime.currentWorkingDir / "_export") in
  BuildSandbox.exportBuild ~outputPrefixPath ~cfg:proj.projcfg.cfg buildPath

let exportDependencies (proj : Project.WithWorkflow.t) () =
  let open RunAsync.Syntax in

  let%bind solved = Project.solved proj in
  let%bind configured = Project.configured proj in

  let exportBuild (_, pkg) =
    match BuildSandbox.Plan.get configured.Project.WithWorkflow.plan pkg.Package.id with
    | None -> return ()
    | Some task ->
      let%lwt () = Logs_lwt.app (fun m -> m "Exporting %s@%a" pkg.name Version.pp pkg.version) in
      let buildPath = BuildSandbox.Task.installPath proj.projcfg.cfg task in
      if%bind Fs.exists buildPath
      then
        let outputPrefixPath = Path.(EsyRuntime.currentWorkingDir / "_export") in
        BuildSandbox.exportBuild ~outputPrefixPath ~cfg:proj.projcfg.cfg buildPath
      else (
        errorf
          "%s@%a was not built, run 'esy build' first"
          pkg.name Version.pp pkg.version
      )
  in

  RunAsync.List.mapAndWait
    ~concurrency:8
    ~f:exportBuild
    (Solution.allDependenciesBFS (Solution.root solved.Project.solution).id solved.solution)

let importBuild (projcfg : ProjectConfig.t) fromPath buildPaths () =
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
    ~f:(fun path -> BuildSandbox.importBuild ~cfg:projcfg.cfg path)
    buildPaths

let importDependencies (proj : Project.WithWorkflow.t) fromPath () =
  let open RunAsync.Syntax in

  let%bind solved = Project.solved proj in
  let%bind fetched = Project.fetched proj in
  let%bind configured = Project.configured proj in

  let fromPath = match fromPath with
    | Some fromPath -> fromPath
    | None -> Path.(proj.projcfg.cfg.buildCfg.projectPath / "_export")
  in

  let importBuild (_direct, pkg) =
    match BuildSandbox.Plan.get configured.Project.WithWorkflow.plan pkg.Package.id with
    | Some task ->
      if%bind BuildSandbox.isBuilt fetched.Project.sandbox task
      then return ()
      else (
        let id = (Scope.id task.scope) in
        let pathDir = Path.(fromPath / BuildId.show id) in
        let pathTgz = Path.(fromPath / (BuildId.show id ^ ".tar.gz")) in
        if%bind Fs.exists pathDir
        then BuildSandbox.importBuild ~cfg:proj.projcfg.cfg pathDir
        else if%bind Fs.exists pathTgz
        then BuildSandbox.importBuild ~cfg:proj.projcfg.cfg pathTgz
        else
          let%lwt () =
            Logs_lwt.warn (fun m -> m "no prebuilt artifact found for %a" BuildId.pp id)
          in return ()
      )
    | None -> return ()
  in

  RunAsync.List.mapAndWait
    ~concurrency:16
    ~f:importBuild
    (Solution.allDependenciesBFS (Solution.root solved.Project.solution).id solved.Project.solution)

let show (projcfg : ProjectConfig.t) _asJson req () =
  let open EsySolve in
  let open RunAsync.Syntax in
  let%bind (req : EsyInstall.Req.t) = RunAsync.ofStringError (EsyInstall.Req.parse req) in
  let%bind resolver = Resolver.make ~cfg:projcfg.solveCfg ~sandbox:projcfg.spec () in
  let%bind resolutions =
    RunAsync.contextf (
      Resolver.resolve ~name:req.name ~spec:req.spec resolver
    ) "resolving %a" EsyInstall.Req.pp req
  in
  match req.spec with
  | EsyInstall.VersionSpec.Npm [[EsyInstall.SemverVersion.Constraint.ANY]]
  | EsyInstall.VersionSpec.Opam [[EsyInstall.OpamPackageVersion.Constraint.ANY]] ->
    let f (res : EsyInstall.PackageConfig.Resolution.t) = match res.resolution with
    | Version v -> `String (Version.showSimple v)
    | _ -> failwith "unreachable"
    in
    `Assoc ["name", `String req.name; "versions", `List (List.map ~f resolutions)]
    |> Yojson.Safe.pretty_to_string
    |> print_endline;
    return ()
  | _ ->
    match resolutions with
    | [] -> errorf "No package found for %a" EsyInstall.Req.pp req
    | resolution::_ ->
      let%bind pkg = RunAsync.contextf (
          Resolver.package ~resolution resolver
        ) "resolving metadata %a" EsyInstall.PackageConfig.Resolution.pp resolution
      in
      let%bind pkg = RunAsync.ofStringError pkg in
      Package.to_yojson pkg
      |> Yojson.Safe.pretty_to_string
      |> print_endline;
      return ()

let default (proj : Project.WithWorkflow.t) cmd () =
  let open RunAsync.Syntax in
  let%lwt fetched = Project.fetched proj in
  match fetched, cmd with
  | Ok _, _ ->
    begin match cmd with
    | Some cmd -> devExec proj cmd ()
    | None -> build proj None ()
    end
  | Error _, None ->
    Logs_lwt.app (fun m -> m "esy %s" EsyRuntime.version);%lwt
    let%bind () = solveAndFetch proj.projcfg () in
    let%bind proj, _ = Project.WithWorkflow.make proj.projcfg in
    build proj None ()
  | Error _ as err, Some _ ->
    Lwt.return err

let release (proj : Project.WithWorkflow.t) () =
  let open RunAsync.Syntax in

  let%bind solved = Project.solved proj in
  let%bind fetched = Project.fetched proj in

  let%bind outputPath =
    let outputDir = "_release" in
    let outputPath = Path.(proj.projcfg.cfg.buildCfg.projectPath / outputDir) in
    let%bind () = Fs.rmPath outputPath in
    return outputPath
  in

  let%bind () = build proj None () in

  let%bind ocamlopt =
    let%bind p = ocaml proj in
    return Path.(p / "bin" / "ocamlopt")
  in

  NpmReleaseCommand.make
    ~ocamlopt
    ~outputPath
    ~concurrency:EsyRuntime.concurrency
    proj.projcfg.ProjectConfig.cfg
    fetched.Project.sandbox
    (Solution.root solved.Project.solution)

let commonSection = "COMMON COMMANDS"
let aliasesSection = "ALIASES"
let introspectionSection = "INTROSPECTION COMMANDS"
let lowLevelSection = "LOW LEVEL PLUMBING COMMANDS"
let otherSection = "OTHER COMMANDS"

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
      Cli.runAsyncToCmdlinerRet (
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
  let info =
    Cmdliner.Term.info
      alias
      ~version:EsyRuntime.version
      ~doc
      ~docs:aliasesSection
  in
  term, info

let makeCommands ~sandbox () =
  let open Cmdliner in

  let commonOpts = ProjectConfig.term sandbox in

  let defaultCommand =
    let cmdTerm =
      Cli.cmdOptionTerm
        ~doc:"Command to execute within the sandbox environment."
        ~docv:"COMMAND"
    in
    makeCommand
      ~header:`No
      ~name:"esy"
      ~doc:"package.json workflow for native development with Reason/OCaml"
      ~docs:commonSection
      Term.(
        const default
        $ Project.WithWorkflow.term sandbox
        $ cmdTerm
        $ Cli.setupLogTerm
      )
  in

  let commands =

    let buildCommand =

      let run projcfg cmd () =
        let%lwt () =
          match cmd with
          | None -> Logs_lwt.app (fun m -> m "esy build %s" EsyRuntime.version)
          | Some _ -> Lwt.return ()
        in
        build ~buildOnly:true projcfg cmd ()
      in

      makeCommand
        ~header:`No
        ~name:"build"
        ~doc:"Build the entire sandbox"
        ~docs:commonSection
        Term.(
          const run
          $ Project.WithWorkflow.term sandbox
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
        ~docs:commonSection
        Term.(
          const solveAndFetch
          $ commonOpts
          $ Cli.setupLogTerm
        )
    in

    [

    (* COMMON COMMANDS *)

    installCommand;
    buildCommand;

    makeCommand
      ~name:"build-shell"
      ~doc:"Enter the build shell"
      ~docs:commonSection
      Term.(
        const buildShell
        $ Project.WithWorkflow.term sandbox
        $ Arg.(
            value
            & pos 0 PkgArg.conv PkgArg.root
            & info [] ~doc:"Package" ~docv:"PACKAGE"
          )
        $ Cli.setupLogTerm
      );

    makeCommand
      ~header:`No
      ~name:"shell"
      ~doc:"Enter esy sandbox shell"
      ~docs:commonSection
      Term.(
        const devShell
        $ Project.WithWorkflow.term sandbox
        $ Cli.setupLogTerm
      );

    makeCommand
      ~header:`No
      ~name:"x"
      ~doc:"Execute command as if the package is installed"
      ~docs:commonSection
      Term.(
        const exec
        $ Project.WithWorkflow.term sandbox
        $ Cli.cmdTerm
            ~doc:"Command to execute within the sandbox environment."
            ~docv:"COMMAND"
            (Cmdliner.Arg.pos_all)
        $ Cli.setupLogTerm
      );

    makeCommand
      ~name:"add"
      ~doc:"Add a new dependency"
      ~docs:commonSection
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
      ~name:"show"
      ~doc:"Display information about available packages"
      ~docs:commonSection
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
      ~docs:commonSection
      Term.(ret (
        const (fun () -> `Help (`Auto, None))
        $ const ()
      ));

    makeCommand
      ~name:"version"
      ~doc:"Print esy version and exit"
      ~docs:commonSection
      Term.(
        const (fun () -> print_endline EsyRuntime.version; RunAsync.return())
        $ const ()
      );

    (* ALIASES *)

    makeAlias buildCommand "b";
    makeAlias installCommand "i";

    (* OTHER COMMANDS *)

    makeCommand
      ~name:"release"
      ~doc:"Produce npm package with prebuilt artifacts"
      ~docs:otherSection
      Term.(
        const release
        $ Project.WithWorkflow.term sandbox
        $ Cli.setupLogTerm
      );

    makeCommand
      ~name:"export-build"
      ~doc:"Export build from the store"
      ~docs:otherSection
      Term.(
        const exportBuild
        $ Project.WithWorkflow.term sandbox
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
      ~docs:otherSection
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
      ~name:"export-dependencies"
      ~doc:"Export sandbox dependendencies as prebuilt artifacts"
      ~docs:otherSection
      Term.(
        const exportDependencies
        $ Project.WithWorkflow.term sandbox
        $ Cli.setupLogTerm
      );

    makeCommand
      ~name:"import-dependencies"
      ~doc:"Import sandbox dependencies"
      ~docs:otherSection
      Term.(
        const importDependencies
        $ Project.WithWorkflow.term sandbox
        $ Arg.(
            value
            & pos 0  (some resolvedPathTerm) None
            & info [] ~doc:"Path with builds."
          )
        $ Cli.setupLogTerm
      );

    (* INTROSPECTION COMMANDS *)

    makeCommand
      ~name:"ls-builds"
      ~doc:"Output a tree of packages in the sandbox along with their status"
      ~docs:introspectionSection
      Term.(
        const lsBuilds
        $ Project.WithWorkflow.term sandbox
        $ Arg.(
            value
            & flag
            & info ["T"; "include-transitive"] ~doc:"Include transitive dependencies")
        $ Cli.setupLogTerm
      );

    makeCommand
      ~name:"ls-libs"
      ~doc:"Output a tree of packages along with the set of libraries made available by each package dependency."
      ~docs:introspectionSection
      Term.(
        const lsLibs
        $ Project.WithWorkflow.term sandbox
        $ Arg.(
            value
            & flag
            & info ["T"; "include-transitive"] ~doc:"Include transitive dependencies")
        $ Cli.setupLogTerm
      );

    makeCommand
      ~name:"ls-modules"
      ~doc:"Output a tree of packages along with the set of libraries and modules made available by each package dependency."
      ~docs:introspectionSection
      Term.(
        const lsModules
        $ Project.WithWorkflow.term sandbox
        $ Arg.(
            value
            & (pos_all string [])
            & info [] ~docv:"LIB" ~doc:"Output modules only for specified lib(s)")
        $ Cli.setupLogTerm
      );

    makeCommand
      ~header:`No
      ~name:"status"
      ~doc:"Print esy sandbox status"
      ~docs:introspectionSection
      Term.(
        const status
        $ Project.WithWorkflow.promiseTerm sandbox
        $ Arg.(value & flag & info ["json"] ~doc:"Format output as JSON")
        $ Cli.setupLogTerm
      );

    makeCommand
      ~header:`No
      ~name:"build-plan"
      ~doc:"Print build plan to stdout"
      ~docs:introspectionSection
      Term.(
        const buildPlan
        $ Project.WithWorkflow.term sandbox
        $ Arg.(
            value
            & pos 0 PkgArg.conv PkgArg.root
            & info [] ~doc:"Package" ~docv:"PACKAGE"
          )
        $ Cli.setupLogTerm
      );

    makeCommand
      ~header:`No
      ~name:"build-env"
      ~doc:"Print build environment to stdout"
      ~docs:introspectionSection
      Term.(
        const buildEnv
        $ Project.WithWorkflow.term sandbox
        $ Arg.(value & flag & info ["json"]  ~doc:"Format output as JSON")
        $ Arg.(
            value
            & pos 0 PkgArg.conv PkgArg.root
            & info [] ~doc:"Package" ~docv:"PACKAGE"
          )
        $ Cli.setupLogTerm
      );

    makeCommand
      ~header:`No
      ~name:"command-env"
      ~doc:"Print command environment to stdout"
      ~docs:introspectionSection
      Term.(
        const commandEnv
        $ Project.WithWorkflow.term sandbox
        $ Arg.(value & flag & info ["json"]  ~doc:"Format output as JSON")
        $ Arg.(
            value
            & pos 0 PkgArg.conv PkgArg.root
            & info [] ~doc:"Package" ~docv:"PACKAGE"
          )
        $ Cli.setupLogTerm
      );

    makeCommand
      ~header:`No
      ~name:"exec-env"
      ~doc:"Print exec environment to stdout"
      ~docs:introspectionSection
      Term.(
        const execEnv
        $ Project.WithWorkflow.term sandbox
        $ Arg.(value & flag & info ["json"]  ~doc:"Format output as JSON")
        $ Arg.(
            value
            & pos 0 PkgArg.conv PkgArg.root
            & info [] ~doc:"Package" ~docv:"PACKAGE"
          )
        $ Cli.setupLogTerm
      );

    (* LOW LEVEL PLUMBING COMMANDS *)

    makeCommand
      ~name:"build-package"
      ~doc:"Build a specified package"
      ~docs:lowLevelSection
      Term.(
        const buildPackage
        $ Project.WithoutWorkflow.term sandbox
        $ Arg.(
            value
            & flag
            & info ["release"]
              ~doc:{|Force to use "esy.build" commands (by default "esy.buildDev" commands are used)|}
          )
        $ Arg.(
            value
            & opt (some depspecConv) None
            & info ["link-depspec"] ~doc:"What to add to the env" ~docv:"DEPSPEC"
          )
        $ Arg.(
            value
            & pos 0 PkgArg.conv PkgArg.root
            & info [] ~doc:"Package to run the build for" ~docv:"PACKAGE"
          )
        $ Cli.setupLogTerm
      );

    makeCommand
      ~name:"build-dependencies"
      ~doc:"Build dependencies for a specified package"
      ~docs:lowLevelSection
      Term.(
        const buildDependencies
        $ Project.WithoutWorkflow.term sandbox
        $ Arg.(
            value
            & flag
            & info ["release"]
              ~doc:{|Force to "esy.build" commands (by default "esy.buildDev" commands are used)|}
          )
        $ Arg.(
            value
            & flag
            & info ["all"] ~doc:"Build all dependencies (including linked packages)"
          )
        $ Arg.(
            value
            & flag
            & info ["devDependencies"] ~doc:"Build devDependencies too"
          )
        $ Arg.(
            value
            & opt (some depspecConv) None
            & info ["link-depspec"]
              ~doc:"Define DEPSPEC expression for linked packages' build environments"
              ~docv:"DEPSPEC"
          )
        $ Arg.(
            value
            & pos 0 PkgArg.conv PkgArg.root
            & info [] ~doc:"Package to build dependencies for" ~docv:"PACKAGE"
          )
        $ Cli.setupLogTerm
      );

    makeCommand
      ~header:`No
      ~name:"exec-command"
      ~doc:"Execute command in a given environment"
      ~docs:lowLevelSection
      Term.(
        const execCommand
        $ Project.WithoutWorkflow.term sandbox
        $ Arg.(
            value
            & flag
            & info ["release"]
              ~doc:{|Force to "esy.build" commands (by default "esy.buildDev" commands are used)|}
          )
        $ Arg.(
            value
            & flag
            & info ["build-context"]
              ~doc:"Initialize package's build context before executing the command"
          )
        $ Arg.(value & flag & info ["include-build-env"]  ~doc:"Include build environment")
        $ Arg.(value & flag & info ["include-current-env"]  ~doc:"Include current environment")
        $ Arg.(value & flag & info ["include-npm-bin"]  ~doc:"Include npm bin in PATH")
        $ Arg.(
            value
            & opt (some depspecConv) None
            & info ["link-depspec"]
              ~doc:"Define DEPSPEC expression for linked packages' build environments"
              ~docv:"DEPSPEC"
          )
        $ Arg.(
            value
            & opt (some depspecConv) None
            & info ["envspec"]
              ~doc:"Define DEPSPEC expression the command execution environment"
              ~docv:"DEPSPEC"
          )
        $ Arg.(
            required
            & pos 0 (some PkgArg.conv) None
            & info [] ~doc:"Package in which environment execute the command" ~docv:"PACKAGE"
          )
        $ Cli.cmdTerm
            ~doc:"Command to execute within the environment."
            ~docv:"COMMAND"
            (Cmdliner.Arg.pos_right 0)
        $ Cli.setupLogTerm
      );

    makeCommand
      ~header:`No
      ~name:"print-env"
      ~doc:"Print a configured environment on stdout"
      ~docs:lowLevelSection
      Term.(
        const printEnv
        $ Project.WithoutWorkflow.term sandbox
        $ Arg.(value & flag & info ["json"]  ~doc:"Format output as JSON")
        $ Arg.(value & flag & info ["include-build-env"]  ~doc:"Include build environment")
        $ Arg.(value & flag & info ["include-current-env"]  ~doc:"Include current environment")
        $ Arg.(value & flag & info ["include-npm-bin"]  ~doc:"Include npm bin in PATH")
        $ Arg.(
            value
            & opt (some depspecConv) None
            & info ["link-depspec"]
              ~doc:"Define DEPSPEC expression for linked packages' build environments"
              ~docv:"DEPSPEC"
          )
        $ Arg.(
            value
            & opt (some depspecConv) None
            & info ["envspec"]
              ~doc:"Define DEPSPEC expression the command execution environment"
              ~docv:"DEPSPEC"
          )
        $ Arg.(
            required
            & pos 0 (some PkgArg.conv) None
            & info [] ~doc:"Package to generate env at" ~docv:"PACKAGE"
          )
        $ Cli.setupLogTerm
      );

    makeCommand
      ~name:"solve"
      ~doc:"Solve dependencies and store the solution"
      ~docs:lowLevelSection
      Term.(
        const solve
        $ commonOpts
        $ Cli.setupLogTerm
      );

    makeCommand
      ~name:"fetch"
      ~doc:"Fetch dependencies using the stored solution"
      ~docs:lowLevelSection
      Term.(
        const fetch
        $ commonOpts
        $ Cli.setupLogTerm
      );

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
