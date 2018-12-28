open Esy
open EsyPackageConfig

module SandboxSpec = EsyInstall.SandboxSpec
module Installation = EsyInstall.Installation
module Solution = EsyInstall.Solution
module SolutionLock = EsyInstall.SolutionLock
module Package = EsyInstall.Package
module PkgSpec = EsyInstall.PkgSpec

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

let modeConv =
  let open Cmdliner in
  let open Result.Syntax in
  let pp fmt v =
    match v with
    | BuildSpec.Build -> Fmt.unit "release" fmt ()
    | BuildSpec.BuildDev -> Fmt.unit "dev" fmt ()
    | BuildSpec.BuildDevForce -> Fmt.unit "force-dev" fmt ()
  in
  let parse v =
    match v with
    | "release" -> return BuildSpec.Build
    | "dev" -> return BuildSpec.BuildDev
    | unknown ->
      let msg = Format.asprintf
        "unknown build mode %s must be %a or %a"
        unknown pp BuildSpec.Build pp BuildSpec.BuildDev
      in
      Error (`Msg msg)
  in
  Arg.conv ~docv:"MODE" (parse, pp)

let planArg =
  let make root link =
    {Workflow.defaultPlanForDev with root; link;}
  in
  Cmdliner.Term.(
    const make
    $ Cmdliner.Arg.(
        value
        & opt modeConv BuildSpec.BuildDev
        & info ["root-mode"]
          ~doc:{|Define build mode for the root|}
      )
    $ Cmdliner.Arg.(
        value
        & opt modeConv BuildSpec.Build
        & info ["link-mode"]
          ~doc:{|Define build mode for linked packages|}
      )
  )

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

let buildDependencies
  all
  devDependencies
  plan
  linkDepspec
  pkgspec
  (proj : Project.WithoutWorkflow.t) =
  let open RunAsync.Syntax in
  let%bind fetched = Project.fetched proj in
  let f (pkg : Package.t) =
    let buildspec =
      let deps =
        match linkDepspec with
        | Some depspec -> depspec
        | None -> Workflow.defaultDepspecForLink
      in
      {Workflow.default.buildspec with buildLink = Some deps}
    in
    let%bind plan = RunAsync.ofRun (
      BuildSandbox.makePlan
        buildspec
        plan
        fetched.Project.sandbox
    ) in
    Project.buildDependencies
      ~buildLinked:all
      ~buildDevDependencies:devDependencies
      proj
      plan
      pkg
  in
  Project.withPackage proj pkgspec f

let buildPackage plan depspec pkgspec (proj : Project.WithoutWorkflow.t)  =
  let open RunAsync.Syntax in

  let%bind fetched = Project.fetched proj in

  let buildspec =
    let deps =
      match depspec with
      | Some depspec -> depspec
      | None -> Workflow.defaultDepspec
    in
    {
      Workflow.default.buildspec
      with buildLink = Some deps;
    }
  in

  let f (pkg : Package.t) =
    let%bind plan = RunAsync.ofRun (
      BuildSandbox.makePlan
        buildspec
        plan
        fetched.Project.sandbox
    ) in
    Project.buildPackage
      ~quiet:true
      ~buildOnly:true
      proj.projcfg
      fetched.Project.sandbox
      plan
      pkg
  in
  Project.withPackage proj pkgspec f

let execCommand
  buildIsInProgress
  includeBuildEnv
  includeCurrentEnv
  includeEsyIntrospectionEnv
  includeNpmBin
  plan
  linkDepspec
  envspec
  pkgspec
  cmd
  (proj : _ Project.project)
  =
  let envspec = {
    EnvSpec.
    buildIsInProgress;
    includeBuildEnv;
    includeCurrentEnv;
    includeNpmBin;
    includeEsyIntrospectionEnv;
    augmentDeps = envspec;
  } in
  let buildspec =
    let deps =
      match linkDepspec with
      | Some depspec -> depspec
      | None -> Workflow.defaultDepspecForLink
    in
    {Workflow.default.buildspec with buildLink = Some deps;}
  in
  Project.execCommand
    ~checkIfDependenciesAreBuilt:false
    ~buildDevDependencies:false
    ~buildLinked:false
    proj
    envspec
    buildspec
    plan
    pkgspec
    cmd
    ()

let printEnv
  asJson
  includeBuildEnv
  includeCurrentEnv
  includeEsyIntrospectionEnv
  includeNpmBin
  plan
  linkDepspec
  envspec
  pkgspec
  (proj : _ Project.project)
  =
  let envspec = {
    EnvSpec.
    buildIsInProgress = false;
    includeBuildEnv;
    includeCurrentEnv;
    includeEsyIntrospectionEnv;
    includeNpmBin;
    augmentDeps = envspec;
  } in
  let buildspec =
    let deps =
      match linkDepspec with
      | Some depspec -> depspec
      | None -> Workflow.defaultDepspecForLink
    in
    {Workflow.default.buildspec with buildLink = Some deps;}
  in
  Project.printEnv
    proj
    envspec
    buildspec
    plan
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
    rootPackageConfigPath : Path.t option;
  } [@@deriving to_yojson]

  let notAProject = {
    isProject = false;
    isProjectSolved = false;
    isProjectFetched = false;
    isProjectReadyForDev = false;
    rootBuildPath = None;
    rootInstallPath = None;
    rootPackageConfigPath = None;
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
          (BuildSandbox.Plan.all configured.Project.WithWorkflow.planForDev)
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
      let%lwt rootPackageConfigPath =
        let open RunAsync.Syntax in
        let%bind fetched = Project.fetched proj in
        return (BuildSandbox.rootPackageConfigPath fetched.Project.sandbox)
      in
      return {
        isProject = true;
        isProjectSolved;
        isProjectFetched;
        isProjectReadyForDev = Result.getOr false built;
        rootBuildPath = Result.getOr None rootBuildPath;
        rootInstallPath = Result.getOr None rootInstallPath;
        rootPackageConfigPath = Result.getOr None rootPackageConfigPath;
      }
    in
    Format.fprintf
      Format.std_formatter
      "%a@."
      Json.Print.ppRegular
      (Status.to_yojson status);
  return ()

let buildPlan pkgspec (proj : Project.WithWorkflow.t) =
  let open RunAsync.Syntax in

  let%bind configured = Project.configured proj in

  let f (pkg : Package.t) =
    match BuildSandbox.Plan.get configured.Project.WithWorkflow.planForDev pkg.id with
    | Some task ->
      let json = BuildSandbox.Task.to_yojson task in
      let data = Yojson.Safe.pretty_to_string json in
      print_endline data;
      return ()
    | None -> errorf "not build defined for %a" PkgArg.pp pkgspec
  in
  Project.withPackage proj pkgspec f

let buildShell pkgspec (proj : Project.WithWorkflow.t) =
  let open RunAsync.Syntax in

  let%bind fetched = Project.fetched proj in
  let%bind configured = Project.configured proj in

  let f (pkg : Package.t) =
    let%bind () =
      Project.buildDependencies
        ~buildLinked:true
        ~buildDevDependencies:false
        proj
        configured.Project.WithWorkflow.planForDev
        pkg
    in
    let p =
      BuildSandbox.buildShell
        configured.Project.WithWorkflow.workflow.buildspec
        Workflow.defaultPlanForDev
        fetched.Project.sandbox
        pkg.id
    in
    match%bind p with
    | Unix.WEXITED 0 -> return ()
    | Unix.WEXITED n
    | Unix.WSTOPPED n
    | Unix.WSIGNALED n -> exit n
  in
  Project.withPackage proj pkgspec f

let build ?(buildOnly=true) ?(release=false) (proj : Project.WithWorkflow.t) cmd () =
  let open RunAsync.Syntax in

  let%bind fetched = Project.fetched proj in
  let%bind configured = Project.configured proj in

  let%bind plan =
    RunAsync.ofRun (
      let open Run.Syntax in
      if release
      then
        BuildSandbox.makePlan
          Workflow.default.buildspec
          Workflow.defaultPlanForRelease
          fetched.Project.sandbox
      else
        return configured.Project.WithWorkflow.planForDev
    )
  in

  begin match cmd with
  | None ->
    let%bind () =
      Project.buildDependencies
        ~buildLinked:true
        ~buildDevDependencies:true
        proj
        plan
        configured.Project.WithWorkflow.root.pkg
    in
    Project.buildPackage
      ~quiet:true
      ~buildOnly
      proj.projcfg
      fetched.Project.sandbox
      plan
      configured.Project.WithWorkflow.root.pkg
  | Some cmd ->
    let%bind () =
      Project.buildDependencies
        ~buildLinked:true
        ~buildDevDependencies:true
        proj
        plan
        configured.Project.WithWorkflow.root.pkg
    in
    Project.execCommand
      ~checkIfDependenciesAreBuilt:false
      ~buildLinked:false
      ~buildDevDependencies:false
      proj
      configured.workflow.buildenvspec
      configured.workflow.buildspec
      (if release
      then BuildSandbox.Plan.plan plan
      else Workflow.defaultPlanForDevForce)
      PkgArg.root
      cmd
      ()
  end

let buildEnv asJson packagePath (proj : Project.WithWorkflow.t) =
  let open RunAsync.Syntax in
  let%bind configured = Project.configured proj in
  Project.printEnv
    ~name:"Build environment"
    proj
    configured.Project.WithWorkflow.workflow.buildenvspec
    configured.Project.WithWorkflow.workflow.buildspec
    Workflow.defaultPlanForDev
    asJson
    packagePath
    ()

let commandEnv asJson packagePath (proj : Project.WithWorkflow.t) =
  let open RunAsync.Syntax in
  let%bind configured = Project.configured proj in
  Project.printEnv
    ~name:"Command environment"
    proj
    configured.Project.WithWorkflow.workflow.commandenvspec
    configured.Project.WithWorkflow.workflow.buildspec
    Workflow.defaultPlanForDev
    asJson
    packagePath
    ()

let execEnv asJson packagePath (proj : Project.WithWorkflow.t) =
  let open RunAsync.Syntax in
  let%bind configured = Project.configured proj in
  Project.printEnv
    ~name:"Exec environment"
    proj
    configured.Project.WithWorkflow.workflow.execenvspec
    configured.Project.WithWorkflow.workflow.buildspec
    Workflow.defaultPlanForDev
    asJson
    packagePath
    ()

let exec release cmd (proj : Project.WithWorkflow.t) =
  let open RunAsync.Syntax in
  let%bind configured = Project.configured proj in
  let%bind () = build ~release ~buildOnly:false proj None () in
  Project.execCommand
    ~checkIfDependenciesAreBuilt:false (* not needed as we build an entire sandbox above *)
    ~buildLinked:false
    ~buildDevDependencies:false
    proj
    configured.Project.WithWorkflow.workflow.execenvspec
    configured.Project.WithWorkflow.workflow.buildspec
    (if release then Workflow.defaultPlanForRelease else Workflow.defaultPlanForDev)
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
    | Parsed args ->
      let args, spec = peekArgs args in
      Command.Parsed args, spec
    | Unparsed line ->
      let args, spec = peekArgs (Astring.String.cuts ~sep:" " line) in
      Command.Unparsed (String.concat " " args), spec
  in

  let%bind cmd = RunAsync.ofRun (
    let open Run.Syntax in

    let id = configured.root.pkg.id in
    let%bind env, scope =
      BuildSandbox.configure
        envspec
        configured.workflow.buildspec
        Workflow.defaultPlanForDev
        fetched.Project.sandbox
        id
    in
    let%bind env = Run.ofStringError (Scope.SandboxEnvironment.Bindings.eval env) in

    let expand v =
      let%bind v = Scope.render ~env ~buildIsInProgress:envspec.buildIsInProgress scope v in
      return (Scope.SandboxValue.render proj.projcfg.cfg.buildCfg v)
    in

    let%bind scriptArgs =
      match scriptArgs with
      | Parsed args -> Result.List.map ~f:expand args
      | Unparsed line ->
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
    Project.execCommand
      ~checkIfDependenciesAreBuilt:true
      ~buildLinked:false
      ~buildDevDependencies:true
      proj
      configured.workflow.commandenvspec
      configured.workflow.buildspec
      Workflow.defaultPlanForDev
      PkgArg.root
      cmd
      ()

let devShell (proj : Project.WithWorkflow.t) =
  let open RunAsync.Syntax in
  let%bind (configured : Project.WithWorkflow.configured) = Project.configured proj in
  let shell =
    try Sys.getenv "SHELL"
    with Not_found -> "/bin/bash"
  in
  Project.execCommand
    ~checkIfDependenciesAreBuilt:true
    ~buildLinked:false
    ~buildDevDependencies:true
    proj
    configured.workflow.commandenvspec
    configured.workflow.buildspec
    Workflow.defaultPlanForDev
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
      match BuildSandbox.Plan.get configured.Project.WithWorkflow.planForDev id with
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
    | SourceType.Immutable, true ->
      Chalk.green "[built]"
    | _, _ ->
      Chalk.blue "[build pending]"
  in
  let line = Printf.sprintf "%s%s %s" (Scope.name task.scope) version status in
  return line

let lsBuilds includeTransitive (proj : Project.WithWorkflow.t) =
  let open RunAsync.Syntax in
  let%bind fetched = Project.fetched proj in
  let computeTermNode task children =
    let%bind built = BuildSandbox.isBuilt fetched.Project.sandbox task in
    let%bind line = formatPackageInfo ~built task in
    return (Some (TermTree.Node { line; children; }))
  in
  makeLsCommand ~computeTermNode ~includeTransitive proj

let lsLibs includeTransitive (proj : Project.WithWorkflow.t) =
  let open RunAsync.Syntax in
  let%bind fetched = Project.fetched proj in

  let%bind ocamlfind =
    let%bind p = Project.WithWorkflow.ocamlfind proj in
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

let lsModules only (proj : Project.WithWorkflow.t) =
  let open RunAsync.Syntax in

  let%bind fetched = Project.fetched proj in
  let%bind configured = Project.configured proj in

  let%bind ocamlfind =
    let%bind p = Project.WithWorkflow.ocamlfind proj in
    return Path.(p / "bin" / "ocamlfind")
  in
  let%bind ocamlobjinfo =
    let%bind p = Project.WithWorkflow.ocaml proj in
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
  let solvespec = Workflow.default.solvespec in
  let%bind solution = Solver.solve solvespec projcfg.solveSandbox in
  let lockPath = SandboxSpec.solutionLockPath projcfg.solveSandbox.Sandbox.spec in
  let%bind () =
    let%bind digest =
      Sandbox.digest solvespec projcfg.solveSandbox
    in
    EsyInstall.SolutionLock.toPath
      ~digest
      projcfg.installSandbox
      solution
      lockPath
  in
  let unused = Resolver.getUnusedResolutions projcfg.solveSandbox.resolver in
  let%lwt () =
    let log resolution =
      Logs_lwt.warn (
        fun m ->
          m "resolution %a is unused (defined in %a)"
          Fmt.(quote string)
          resolution
          EsyInstall.SandboxSpec.pp
          projcfg.installSandbox.spec
      )
    in
    Lwt_list.iter_s log unused
  in
  return solution

let solve (proj : Project.WithWorkflow.t) =
  let open RunAsync.Syntax in
  let%bind _ : Solution.t = getSandboxSolution proj.projcfg in
  return ()

let fetch (proj : Project.WithWorkflow.t) =
  let open RunAsync.Syntax in
  let lockPath = SandboxSpec.solutionLockPath proj.projcfg.spec in
  match%bind SolutionLock.ofPath proj.projcfg.installSandbox lockPath with
  | Some solution -> EsyInstall.Fetch.fetch proj.projcfg.installSandbox solution
  | None -> error "no lock found, run 'esy solve' first"

let solveAndFetch (proj : Project.WithWorkflow.t) =
  let open RunAsync.Syntax in
  let lockPath = SandboxSpec.solutionLockPath proj.projcfg.spec in
  let solvespec = Workflow.default.solvespec in
  let%bind digest = EsySolve.Sandbox.digest solvespec proj.projcfg.solveSandbox in
  match%bind SolutionLock.ofPath ~digest proj.projcfg.installSandbox lockPath with
  | Some solution ->
    if%bind EsyInstall.Fetch.isInstalled ~sandbox:proj.projcfg.installSandbox solution
    then return ()
    else fetch proj
  | None ->
    let%bind () = solve proj in
    let%bind () = fetch proj in
    return ()

let add (reqs : string list) (proj : Project.WithWorkflow.t) =
  let open EsySolve in
  let open RunAsync.Syntax in
  let opamError =
    "add dependencies manually when working with opam sandboxes"
  in

  let%bind reqs = RunAsync.ofStringError (
    Result.List.map ~f:Req.parse reqs
  ) in

  let projcfg = proj.projcfg in
  let solveSandbox = proj.projcfg.solveSandbox in

  let%bind solveSandbox =
    let addReqs origDeps =
      let open InstallManifest.Dependencies in
      match origDeps with
      | NpmFormula prevReqs -> return (NpmFormula (reqs @ prevReqs))
      | OpamFormula _ -> error opamError
    in
    let%bind combinedDeps = addReqs solveSandbox.root.dependencies in
    let root = { solveSandbox.root with dependencies = combinedDeps } in
    return { solveSandbox with root; }
  in

  let projcfg = {projcfg with solveSandbox;} in

  let%bind solution = getSandboxSolution projcfg in
  let%bind () = fetch {proj with projcfg;} in

  let%bind addedDependencies, configPath =
    let records =
      let f (record : EsyInstall.Package.t) _ map =
        StringMap.add record.name record map
      in
      Solution.fold ~f ~init:StringMap.empty solution
    in
    let addedDependencies =
      let f {Req. name; _} =
        match StringMap.find name records with
        | Some record ->
          let constr =
            match record.EsyInstall.Package.version with
            | Version.Npm version ->
              SemverVersion.Formula.DNF.show
                (SemverVersion.caretRangeOfVersion version)
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
      let spec = projcfg.solveSandbox.Sandbox.spec in
      match spec.manifest with
      | EsyInstall.SandboxSpec.Manifest (Esy, fname) -> return Path.(spec.SandboxSpec.path / fname)
      | Manifest (Opam, _) -> error opamError
      | ManifestAggregate _ -> error opamError
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
        let%bind solveSandbox =
          EsySolve.Sandbox.make
            ~cfg:solveSandbox.cfg
            solveSandbox.spec
        in
        let projcfg = {projcfg with solveSandbox} in
        let%bind digest =
          EsySolve.Sandbox.digest
            Workflow.default.solvespec
            projcfg.solveSandbox
        in
        (* we can only do this because we keep invariant that the constraint we
         * save in manifest covers the installed version *)
        EsyInstall.SolutionLock.unsafeUpdateChecksum
          ~digest
          (SandboxSpec.solutionLockPath solveSandbox.spec)
      in
      return ()

let exportBuild buildPath (proj : Project.WithWorkflow.t) =
  let outputPrefixPath = Path.(EsyRuntime.currentWorkingDir / "_export") in
  BuildSandbox.exportBuild ~outputPrefixPath ~cfg:proj.projcfg.cfg buildPath

let exportDependencies (proj : Project.WithWorkflow.t) =
  let open RunAsync.Syntax in

  let%bind solved = Project.solved proj in
  let%bind configured = Project.configured proj in

  let exportBuild (_, pkg) =
    match BuildSandbox.Plan.get configured.Project.WithWorkflow.planForDev pkg.Package.id with
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

let importBuild fromPath buildPaths (projcfg : ProjectConfig.t) =
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

let importDependencies fromPath (proj : Project.WithWorkflow.t) =
  let open RunAsync.Syntax in

  let%bind solved = Project.solved proj in
  let%bind fetched = Project.fetched proj in
  let%bind configured = Project.configured proj in

  let fromPath = match fromPath with
    | Some fromPath -> fromPath
    | None -> Path.(proj.projcfg.cfg.buildCfg.projectPath / "_export")
  in

  let importBuild (_direct, pkg) =
    match BuildSandbox.Plan.get configured.Project.WithWorkflow.planForDev pkg.Package.id with
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

let show _asJson req (projcfg : ProjectConfig.t) =
  let open EsySolve in
  let open RunAsync.Syntax in
  let%bind (req : Req.t) = RunAsync.ofStringError (Req.parse req) in
  let%bind resolver = Resolver.make ~cfg:projcfg.solveSandbox.cfg ~sandbox:projcfg.spec () in
  let%bind resolutions =
    RunAsync.contextf (
      Resolver.resolve ~name:req.name ~spec:req.spec resolver
    ) "resolving %a" Req.pp req
  in
  match req.spec with
  | VersionSpec.Npm [[SemverVersion.Constraint.ANY]]
  | VersionSpec.Opam [[OpamPackageVersion.Constraint.ANY]] ->
    let f (res : Resolution.t) = match res.resolution with
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
        ) "resolving metadata %a" Resolution.pp resolution
      in
      let%bind pkg = RunAsync.ofStringError pkg in
      InstallManifest.to_yojson pkg
      |> Yojson.Safe.pretty_to_string
      |> print_endline;
      return ()

let printHeader ?spec name =
  match spec with
  | Some spec ->
    let needReportProjectPath =
      Path.compare
        spec.EsyInstall.SandboxSpec.path
        EsyRuntime.currentWorkingDir
        <> 0
    in
    if needReportProjectPath
    then
      Logs_lwt.app (fun m -> m
        "%s %s (using %a)@;found project at %a"
        name EsyRuntime.version
        EsyInstall.SandboxSpec.pp spec
        Path.ppPretty spec.path
      )
    else
      Logs_lwt.app (fun m -> m
        "%s %s (using %a)"
        name EsyRuntime.version
        EsyInstall.SandboxSpec.pp spec
      )
  | None ->
    Logs_lwt.app (fun m -> m
      "%s %s"
      name EsyRuntime.version
    )

let default cmd (proj : Project.WithWorkflow.t) =
  let open RunAsync.Syntax in
  let%lwt fetched = Project.fetched proj in
  match fetched, cmd with
  | Ok _, None ->
    printHeader ~spec:proj.projcfg.spec "esy";%lwt
    build proj None ()
  | Ok _, Some cmd ->
    devExec proj cmd ()
  | Error _, None ->
    printHeader ~spec:proj.projcfg.spec "esy";%lwt
    let%bind () = solveAndFetch proj in
    let%bind proj, _ = Project.WithWorkflow.make proj.projcfg in
    build proj None ()
  | Error _ as err, Some _ ->
    Lwt.return err

let commonSection = "COMMON COMMANDS"
let aliasesSection = "ALIASES"
let introspectionSection = "INTROSPECTION COMMANDS"
let lowLevelSection = "LOW LEVEL PLUMBING COMMANDS"
let otherSection = "OTHER COMMANDS"

let makeCommand
  ?(header=`Standard)
  ?docs
  ?doc
  ~name
  cmd =
  let info =
    Cmdliner.Term.info
      ~exits:Cmdliner.Term.default_exits
      ?docs
      ?doc
      ~version:EsyRuntime.version
      name
  in
  let cmd =
    let f comp =
      let () =
        match header with
        | `Standard -> Lwt_main.run (printHeader name)
        | `No -> ()
      in
      Cli.runAsyncToCmdlinerRet comp
    in
    Cmdliner.Term.(ret (app (const f) cmd))
  in

  cmd, info

let makeAlias ?(docs=aliasesSection) command alias =
  let term, info = command in
  let name = Cmdliner.Term.name info in
  let doc = Printf.sprintf "An alias for $(b,%s) command" name in
  let info =
    Cmdliner.Term.info
      alias
      ~version:EsyRuntime.version
      ~doc
      ~docs
  in
  term, info

let makeCommands projectPath =
  let open Cmdliner in

  let projectConfig = ProjectConfig.term projectPath in
  let projectWithWorkflow = Project.WithWorkflow.term projectPath in
  let project = Project.WithoutWorkflow.term projectPath in

  let makeProjectWithWorkflowCommand ?(header=`Standard) ?docs ?doc ~name cmd =
    let cmd =
      let run cmd project =
        let () =
          match header with
          | `Standard -> Lwt_main.run (printHeader ~spec:project.Project.projcfg.spec name)
          | `No -> ()
        in
        cmd project
      in
      Cmdliner.Term.(pure run $ cmd $ projectWithWorkflow)
    in
    makeCommand ~header:`No ?docs ?doc ~name cmd
  in

  let makeProjectWithoutWorkflowCommand ?(header=`Standard) ?docs ?doc ~name cmd =
    let cmd =
      let run cmd project =
        let () =
          match header with
          | `Standard -> Lwt_main.run (printHeader ~spec:project.Project.projcfg.spec name)
          | `No -> ()
        in
        cmd project
      in
      Cmdliner.Term.(pure run $ cmd $ project)
    in
    makeCommand ~header:`No ?docs ?doc ~name cmd
  in

  let defaultCommand =
    let cmdTerm =
      Cli.cmdOptionTerm
        ~doc:"Command to execute within the sandbox environment."
        ~docv:"COMMAND"
    in
    makeProjectWithWorkflowCommand
      ~header:`No
      ~name:"esy"
      ~doc:"package.json workflow for native development with Reason/OCaml"
      ~docs:commonSection
      Term.(const default $ cmdTerm)
  in

  let commands =

    let buildCommand =

      let run release cmd proj =
        let () =
          match cmd with
          | None -> Lwt_main.run (printHeader ~spec:proj.Project.projcfg.spec "esy build")
          | Some _ -> ()
        in
        build ~buildOnly:true ~release proj cmd ()
      in

      makeProjectWithWorkflowCommand
        ~header:`No
        ~name:"build"
        ~doc:"Build the entire sandbox"
        ~docs:commonSection
        Term.(
          const run
          $ Arg.(
              value
              & flag
              & info ["release"] ~doc:"Build in release mode"
            )
          $ Cli.cmdOptionTerm
              ~doc:"Command to execute within the build environment."
              ~docv:"COMMAND"
        )
    in

    let installCommand =
      makeProjectWithWorkflowCommand
        ~name:"install"
        ~doc:"Solve & fetch dependencies"
        ~docs:commonSection
        Term.(const solveAndFetch)
    in

    let npmReleaseCommand =
      makeProjectWithWorkflowCommand
        ~name:"npm-release"
        ~doc:"Produce npm package with prebuilt artifacts"
        ~docs:otherSection
        Term.(const NpmReleaseCommand.run)
    in

    [

    (* COMMON COMMANDS *)

    installCommand;
    buildCommand;

    makeProjectWithWorkflowCommand
      ~name:"build-shell"
      ~doc:"Enter the build shell"
      ~docs:commonSection
      Term.(
        const buildShell
        $ Arg.(
            value
            & pos 0 PkgArg.conv PkgArg.root
            & info [] ~doc:"Package" ~docv:"PACKAGE"
          )
      );

    makeProjectWithWorkflowCommand
      ~name:"shell"
      ~doc:"Enter esy sandbox shell"
      ~docs:commonSection
      Term.(const devShell);

    makeProjectWithWorkflowCommand
      ~header:`No
      ~name:"x"
      ~doc:"Execute command as if the package is installed"
      ~docs:commonSection
      Term.(
        const exec
        $ Arg.(
            value
            & flag
            & info ["release"] ~doc:"Build in release mode"
          )
        $ Cli.cmdTerm
            ~doc:"Command to execute within the sandbox environment."
            ~docv:"COMMAND"
            (Cmdliner.Arg.pos_all)
      );

    makeProjectWithWorkflowCommand
      ~name:"add"
      ~doc:"Add a new dependency"
      ~docs:commonSection
      Term.(
        const add
        $ Arg.(
            non_empty
            & pos_all string []
            & info [] ~docv:"PACKAGE" ~doc:"Package to install"
          )
      );

    makeCommand
      ~name:"show"
      ~doc:"Display information about available packages"
      ~docs:commonSection
      ~header:`No
      Term.(
        const show
        $ Arg.(value & flag & info ["json"] ~doc:"Format output as JSON")
        $ Arg.(
            required
            & pos 0 (some string) None
            & info [] ~docv:"PACKAGE" ~doc:"Package to display information about"
          )
        $ projectConfig
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

    npmReleaseCommand;
    makeAlias ~docs:otherSection npmReleaseCommand "release";

    makeProjectWithWorkflowCommand
      ~name:"export-build"
      ~doc:"Export build from the store"
      ~docs:otherSection
      Term.(
        const exportBuild
        $ Arg.(
            required
            & pos 0  (some resolvedPathTerm) None
            & info [] ~doc:"Path with builds."
          )
      );

    makeCommand
      ~name:"import-build"
      ~doc:"Import build into the store"
      ~docs:otherSection
      Term.(
        const importBuild
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
        $ projectConfig
      );

    makeProjectWithWorkflowCommand
      ~name:"export-dependencies"
      ~doc:"Export sandbox dependendencies as prebuilt artifacts"
      ~docs:otherSection
      Term.(const exportDependencies);

    makeProjectWithWorkflowCommand
      ~name:"import-dependencies"
      ~doc:"Import sandbox dependencies"
      ~docs:otherSection
      Term.(
        const importDependencies
        $ Arg.(
            value
            & pos 0  (some resolvedPathTerm) None
            & info [] ~doc:"Path with builds."
          )
      );

    (* INTROSPECTION COMMANDS *)

    makeProjectWithWorkflowCommand
      ~name:"ls-builds"
      ~doc:"Output a tree of packages in the sandbox along with their status"
      ~docs:introspectionSection
      Term.(
        const lsBuilds
        $ Arg.(
            value
            & flag
            & info ["T"; "include-transitive"] ~doc:"Include transitive dependencies")
      );

    makeProjectWithWorkflowCommand
      ~name:"ls-libs"
      ~doc:"Output a tree of packages along with the set of libraries made available by each package dependency."
      ~docs:introspectionSection
      Term.(
        const lsLibs
        $ Arg.(
            value
            & flag
            & info ["T"; "include-transitive"] ~doc:"Include transitive dependencies")
      );

    makeProjectWithWorkflowCommand
      ~name:"ls-modules"
      ~doc:"Output a tree of packages along with the set of libraries and modules made available by each package dependency."
      ~docs:introspectionSection
      Term.(
        const lsModules
        $ Arg.(
            value
            & (pos_all string [])
            & info [] ~docv:"LIB" ~doc:"Output modules only for specified lib(s)")
      );

    makeCommand
      ~header:`No
      ~name:"status"
      ~doc:"Print esy sandbox status"
      ~docs:introspectionSection
      Term.(
        const status
        $ Project.WithWorkflow.promiseTerm projectPath
        $ Arg.(value & flag & info ["json"] ~doc:"Format output as JSON")
        $ Cli.setupLogTerm
      );

    makeProjectWithWorkflowCommand
      ~header:`No
      ~name:"build-plan"
      ~doc:"Print build plan to stdout"
      ~docs:introspectionSection
      Term.(
        const buildPlan
        $ Arg.(
            value
            & pos 0 PkgArg.conv PkgArg.root
            & info [] ~doc:"Package" ~docv:"PACKAGE"
          )
      );

    makeProjectWithWorkflowCommand
      ~header:`No
      ~name:"build-env"
      ~doc:"Print build environment to stdout"
      ~docs:introspectionSection
      Term.(
        const buildEnv
        $ Arg.(value & flag & info ["json"]  ~doc:"Format output as JSON")
        $ Arg.(
            value
            & pos 0 PkgArg.conv PkgArg.root
            & info [] ~doc:"Package" ~docv:"PACKAGE"
          )
      );

    makeProjectWithWorkflowCommand
      ~header:`No
      ~name:"command-env"
      ~doc:"Print command environment to stdout"
      ~docs:introspectionSection
      Term.(
        const commandEnv
        $ Arg.(value & flag & info ["json"]  ~doc:"Format output as JSON")
        $ Arg.(
            value
            & pos 0 PkgArg.conv PkgArg.root
            & info [] ~doc:"Package" ~docv:"PACKAGE"
          )
      );

    makeProjectWithWorkflowCommand
      ~header:`No
      ~name:"exec-env"
      ~doc:"Print exec environment to stdout"
      ~docs:introspectionSection
      Term.(
        const execEnv
        $ Arg.(value & flag & info ["json"]  ~doc:"Format output as JSON")
        $ Arg.(
            value
            & pos 0 PkgArg.conv PkgArg.root
            & info [] ~doc:"Package" ~docv:"PACKAGE"
          )
      );

    (* LOW LEVEL PLUMBING COMMANDS *)

    makeProjectWithoutWorkflowCommand
      ~name:"build-package"
      ~doc:"Build a specified package"
      ~docs:lowLevelSection
      Term.(
        const buildPackage
        $ planArg
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
      );

    makeProjectWithoutWorkflowCommand
      ~name:"build-dependencies"
      ~doc:"Build dependencies for a specified package"
      ~docs:lowLevelSection
      Term.(
        const buildDependencies
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
        $ planArg
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
      );

    makeProjectWithoutWorkflowCommand
      ~header:`No
      ~name:"exec-command"
      ~doc:"Execute command in a given environment"
      ~docs:lowLevelSection
      Term.(
        const execCommand
        $ Arg.(
            value
            & flag
            & info ["build-context"]
              ~doc:"Initialize package's build context before executing the command"
          )
        $ Arg.(value & flag & info ["include-build-env"]  ~doc:"Include build environment")
        $ Arg.(value & flag & info ["include-current-env"]  ~doc:"Include current environment")
        $ Arg.(
            value
            & flag
            & info ["include-esy-introspection-env"]
              ~doc:"Include esy introspection environment"
          )
        $ Arg.(value & flag & info ["include-npm-bin"]  ~doc:"Include npm bin in PATH")
        $ planArg
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
      );

    makeProjectWithoutWorkflowCommand
      ~header:`No
      ~name:"print-env"
      ~doc:"Print a configured environment on stdout"
      ~docs:lowLevelSection
      Term.(
        const printEnv
        $ Arg.(value & flag & info ["json"]  ~doc:"Format output as JSON")
        $ Arg.(value & flag & info ["include-build-env"]  ~doc:"Include build environment")
        $ Arg.(value & flag & info ["include-current-env"]  ~doc:"Include current environment")
        $ Arg.(
            value
            & flag
            & info ["include-esy-introspection-env"]
              ~doc:"Include esy introspection environment"
          )
        $ Arg.(value & flag & info ["include-npm-bin"]  ~doc:"Include npm bin in PATH")
        $ planArg
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
      );

    makeProjectWithWorkflowCommand
      ~name:"solve"
      ~doc:"Solve dependencies and store the solution"
      ~docs:lowLevelSection
      Term.(const solve);

    makeProjectWithWorkflowCommand
      ~name:"fetch"
      ~doc:"Fetch dependencies using the stored solution"
      ~docs:lowLevelSection
      Term.(const fetch);

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

  let argv, commandName, rootPackagePath =
    let argv = Array.to_list Sys.argv in

    let rootPackagePath, argv =
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

    Array.of_list argv, commandName, rootPackagePath
  in

  let defaultCommand, commands = makeCommands rootPackagePath in

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
  | Some "x" ->
    let argv =
      match Array.to_list argv with
      | (_prg::_command::"--help"::[]) as argv -> argv
      | prg::command::"--release"::rest -> prg::command::"--release"::"--"::rest
      | prg::command::rest -> prg::command::"--"::rest
      | argv -> argv
    in
    let argv = Array.of_list argv in
    runCmdliner argv

  | Some "b"
  | Some "build" ->
    let argv =
      match Array.to_list argv with
      | (_prg::_command::"--help"::[]) as argv -> argv
      | prg::command::"--release"::rest -> prg::command::"--release"::"--"::rest
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
