open EsyPackageConfig

module Solution = EsyInstall.Solution
module Package = EsyInstall.Package
module Installation = EsyInstall.Installation

type t = {
  cfg : Config.t;
  arch : System.Arch.t;
  platform : System.Platform.t;
  sandboxEnv : SandboxEnv.t;
  solution : Solution.t;
  installation : Installation.t;
  manifests : BuildManifest.t PackageId.Map.t;
}

let rootPackageConfigPath sandbox =
  let root = Solution.root sandbox.solution in
  match root.source with
  | Link { path; manifest = Some (_kind, filename) } ->
    let path = DistPath.toPath sandbox.cfg.spec.path path in
    Some Path.(path / filename)
  | Link { path = _; manifest = None } -> None
  | Install _ -> None

let readManifests cfg (solution : Solution.t) (installation : Installation.t) =
  let open RunAsync.Syntax in

  Logs_lwt.debug (fun m -> m "reading manifests: start");%lwt

  let readManifest (id, loc) =
    Logs_lwt.debug (fun m ->
      m "reading manifest: %a %a" PackageId.pp id
      Installation.pp_location loc
    );%lwt

    let pkg = Solution.getExn id solution in
    let isRoot = Package.compare (Solution.root solution) pkg = 0 in

    RunAsync.contextf (
      let%bind manifest, paths =
        ReadBuildManifest.ofInstallationLocation
          ~cfg
          pkg
          loc
      in
      match manifest with
      | Some manifest -> return (id, paths, Some manifest)
      | None ->
        if isRoot
        then
          let manifest =
            BuildManifest.empty
              ~name:(Some pkg.name)
              ~version:(Some pkg.version)
              ()
          in
          return (id, paths, Some manifest)
        else
          (* we don't want to track non-esy manifest, hence Path.Set.empty *)
          return (id, Path.Set.empty, None)
    ) "reading manifest %a" PackageId.pp id
  in

  let%bind items =
    RunAsync.List.mapAndJoin
      ~concurrency:100
      ~f:readManifest
      (Installation.entries installation)
  in

  let paths, manifests =
    let f (paths, manifests) (id, manifestPaths, manifest) =
      match manifest with
      | None ->
        let paths = Path.Set.union paths manifestPaths in
        paths, manifests
      | Some manifest ->
        let paths = Path.Set.union paths manifestPaths in
        let manifests = PackageId.Map.add id manifest manifests in
        paths, manifests
    in
    List.fold_left ~f ~init:(Path.Set.empty, PackageId.Map.empty) items
  in

  Logs_lwt.debug (fun m -> m "reading manifests: done");%lwt

  return (paths, manifests)

let make
  ?(sandboxEnv=SandboxEnv.empty)
  cfg
  solution
  installation =
  let open RunAsync.Syntax in
  let%bind paths, manifests = readManifests cfg solution installation in
  return ({
    cfg;
    platform = System.Platform.host;
    arch = System.Arch.host;
    sandboxEnv;
    solution;
    installation;
    manifests;
  }, paths)


let renderExpression sandbox scope expr =
  let open Run.Syntax in
  let%bind expr = Scope.render ~buildIsInProgress:false scope expr in
  return (Scope.SandboxValue.render sandbox.cfg.buildCfg expr)

module Task = struct
  type t = {
    idrepr : BuildId.Repr.t;
    pkg : Package.t;
    scope : Scope.t;
    env : Scope.SandboxEnvironment.t;
    build : Scope.SandboxValue.t list list;
    install : Scope.SandboxValue.t list list option;
    dependencies : PackageId.t list;
  }

  let plan ?env (t : t) =
    let rootPath = Scope.rootPath t.scope in
    let buildPath = Scope.buildPath t.scope in
    let stagePath = Scope.stagePath t.scope in
    let installPath = Scope.installPath t.scope in
    let jbuilderHackEnabled =
      match Scope.buildType t.scope, Scope.sourceType t.scope with
      | JbuilderLike, Transient -> true
      | JbuilderLike, _ -> false
      | InSource, _
      | OutOfSource, _
      | Unsafe, _ -> false
    in
    let env = Option.orDefault ~default:t.env env in
    {
      EsyBuildPackage.Plan.
      id = BuildId.show (Scope.id t.scope);
      name = t.pkg.name;
      version = Version.show t.pkg.version;
      sourceType = Scope.sourceType t.scope;
      buildType = Scope.buildType t.scope;
      build = t.build;
      install = t.install;
      sourcePath = Scope.SandboxPath.toValue (Scope.sourcePath t.scope);
      rootPath = Scope.SandboxPath.toValue rootPath;
      buildPath = Scope.SandboxPath.toValue buildPath;
      stagePath = Scope.SandboxPath.toValue stagePath;
      installPath = Scope.SandboxPath.toValue installPath;
      jbuilderHackEnabled;
      env;
    }

  let to_yojson t = EsyBuildPackage.Plan.to_yojson (plan t)

  let toPathWith cfg t make =
    Scope.SandboxPath.toPath cfg.Config.buildCfg (make t.scope)

  let sourcePath cfg t = toPathWith cfg t Scope.sourcePath
  let buildPath cfg t = toPathWith cfg t Scope.buildPath
  let installPath cfg t = toPathWith cfg t Scope.installPath
  let logPath cfg t = toPathWith cfg t Scope.logPath
  let buildInfoPath cfg t = toPathWith cfg t Scope.buildInfoPath

  let pp fmt task = PackageId.pp fmt task.pkg.id

end

let renderEsyCommands ~env ~buildIsInProgress scope commands =
  let open Run.Syntax in
  let envScope name =
    match Scope.SandboxEnvironment.find name env with
    | Some v -> Some (Scope.SandboxValue.show v)
    | None -> None
  in

  let renderArg v =
    let%bind v = Scope.render ~buildIsInProgress scope v in
    let v = Scope.SandboxValue.show v in
    Run.ofStringError (EsyShellExpansion.render ~scope:envScope v)
  in

  let renderCommand =
    function
    | Command.Parsed args ->
      let f arg =
        let%bind arg = renderArg arg in
        return (Scope.SandboxValue.v arg)
      in
      Result.List.map ~f args
    | Command.Unparsed line ->
      let%bind line = renderArg line in
      let%bind args = ShellSplit.split line in
      return (List.map ~f:Scope.SandboxValue.v args)
  in

  match Result.List.map ~f:renderCommand commands with
  | Ok commands -> Ok commands
  | Error err -> Error err

let renderOpamCommands opamEnv commands =
  let open Run.Syntax in
  try
    let commands = OpamFilter.commands opamEnv commands in
    let commands = List.map ~f:(List.map ~f:Scope.SandboxValue.v) commands in
    return commands
  with
    | Failure msg -> error msg

let renderOpamSubstsAsCommands _opamEnv substs =
  let open Run.Syntax in
  let commands =
    let f path =
      let path = Path.addExt ".in" path in
      [Scope.SandboxValue.v "substs"; Scope.SandboxValue.v (Path.show path)]
    in
    List.map ~f substs
  in
  return commands

let renderOpamPatchesToCommands opamEnv patches =
  let open Run.Syntax in
  Run.context (
    let evalFilter = function
      | path, None -> return (path, true)
      | path, Some filter ->
        let%bind filter =
          try return (OpamFilter.eval_to_bool opamEnv filter)
          with Failure msg -> error msg
        in return (path, filter)
    in

    let%bind filtered = Result.List.map ~f:evalFilter patches in

    let toCommand (path, _) =
      let cmd = ["patch"; "--strip"; "1"; "--input"; Path.show path] in
      List.map ~f:Scope.SandboxValue.v cmd
    in

    return (
      filtered
      |> List.filter ~f:(fun (_, v) -> v)
      |> List.map ~f:toCommand
    )
  ) "processing patch field"


module Reason = struct
  type t =
    | ForBuild
    | ForScope
    [@@deriving ord]

  let (+) a b =
    match a, b with
    | ForBuild, _
    | _, ForBuild -> ForBuild
    | ForScope, ForScope -> ForScope
end

let makeScope
  ?cache
  ?envspec
  ~forceImmutable
  buildspec
  mode
  sandbox
  id
  =
  let open Run.Syntax in

  let updateSeen seen id =
    match List.find_opt ~f:(fun p -> PackageId.compare p id = 0) seen with
    | Some _ -> errorf "@[<h>found circular dependency on: %a@]" PackageId.ppNoHash id
    | None -> return (id::seen)
  in

  let cache =
    match cache with
    | None -> Hashtbl.create 100
    | Some cache -> cache
  in

  let rec visit envspec seen (id : PackageId.t) =
    match Hashtbl.find_opt cache id with
    | Some None -> return None
    | Some (Some res) ->
      let%bind _ : PackageId.t list = updateSeen seen id in
      return (Some res)
    | None ->
      let%bind res =
        match PackageId.Map.find_opt id sandbox.manifests with
        | Some build ->
          let%bind seen = updateSeen seen id in
          Run.contextf (
            let%bind scope, idrepr, directDependencies = visit' envspec seen id build in
            return (Some (scope, build, idrepr, directDependencies))
          ) "processing %a" PackageId.ppNoHash id
        | None -> return None
      in
      Hashtbl.replace cache id res;
      return res

  and visit' envspec seen id buildManifest =
    let module IdS = PackageId.Set in
    let pkg = Solution.getExn id sandbox.solution in
    let location = Installation.findExn id sandbox.installation in

    let build, _commands =
      BuildSpec.classify buildspec mode sandbox.solution pkg buildManifest
    in

    let matchedForBuild =
      DepSpec.eval sandbox.solution pkg.Package.id build.deps
    in

    let matchedForScope =
      match envspec with
      | None -> matchedForBuild
      | Some envspec -> DepSpec.eval sandbox.solution pkg.Package.id envspec
    in

    let annotateWithReason pkgid =
      if IdS.mem pkgid matchedForBuild
      then Reason.ForBuild, pkgid
      else Reason.ForScope, pkgid
    in

    let%bind dependencies =

      let module Seen = Set.Make(struct
        type t = Reason.t * PackageId.t [@@deriving ord]
      end) in

      let collectAllDependencies initDependencies =

        let queue  = Queue.create () in
        let enqueue direct dependencies =
          let f id = Queue.add (direct, id) queue in
          List.iter ~f dependencies;
        in

        let rec process (seen, reasons, dependencies) =
          match Queue.pop queue with
          | exception Queue.Empty -> seen, reasons, dependencies
          | direct, (reason, id) ->
            if Seen.mem (reason, id) seen
            then process (seen, reasons, dependencies)
            else
              let node = Solution.getExn id sandbox.solution in
              let seen = Seen.add (reason, id) seen in
              let dependencies = (direct, node)::dependencies in
              let reasons =
                let f = function
                  | None -> Some reason
                  | Some prevreason -> Some Reason.(reason + prevreason)
                in
                PackageId.Map.update id f reasons
              in
              let next =
                List.map
                  ~f:(fun depid ->
                    let depreason, depid = annotateWithReason depid in
                    depreason, depid)
                  (Solution.traverse node)
              in
              enqueue false next;
              process (seen, reasons, dependencies)
        in

        let _, reasons, dependencies =
          enqueue true initDependencies;
          process (Seen.empty, PackageId.Map.empty, [])
        in

        let _seen, dependencies =
          let f (seen, res) (direct, pkg) =
            if IdS.mem pkg.Package.id seen
            then seen, res
            else
              let seen = IdS.add pkg.id seen in
              let reason = PackageId.Map.find pkg.Package.id reasons in
              seen, ((direct, reason, pkg)::res)
          in
          List.fold_left ~f ~init:(IdS.empty, []) dependencies
        in

        dependencies
      in

      let collect dependencies (direct, reason, pkg) =
        match%bind visit None seen pkg.Package.id with
        | Some (scope, _build, _idrepr, _directDependencies) ->
          let _pkgid = (Scope.pkg scope).id in
          return ((direct, reason, scope)::dependencies)
        | None -> return dependencies
      in
      let lineage =
        let dependencies = PackageId.Set.(
          let set = union matchedForBuild matchedForScope in
          let set = remove pkg.Package.id set in
          List.map ~f:annotateWithReason (elements set)
        ) in
        collectAllDependencies dependencies
      in
      Result.List.foldLeft
        ~f:collect
        ~init:[]
        lineage
    in

    let sourceType =
      match pkg.source with
      | Install _ ->
        let hasTransientDeps =
          let f (_direct, reason, scope) =
            match reason with
            | Reason.ForBuild -> Scope.sourceType scope = SourceType.Transient
            | Reason.ForScope -> false
          in
          List.exists ~f dependencies
        in
        let sourceType =
          if hasTransientDeps
          then SourceType.ImmutableWithTransientDependencies
          else SourceType.Immutable
        in
        sourceType
      | Link _ ->
        SourceType.Transient
    in
    let sourceType =
      if forceImmutable
      then SourceType.Immutable
      else sourceType
    in

    let name = PackageId.name id in
    let version = PackageId.version id in

    let id, idrepr =
      let dependencies =
        let f = function
          | true, Reason.ForBuild, dep -> Some (Scope.id dep)
          | true, Reason.ForScope, _ -> None
          | false, _, _ -> None
        in
        dependencies
        |> List.map ~f
        |> List.filterNone
      in
      BuildId.make
        ~sandboxEnv:sandbox.sandboxEnv
        ~packageId:pkg.id
        ~platform:sandbox.platform
        ~arch:sandbox.arch
        ~build:buildManifest
        ~sourceType
        ~mode:build.mode
        ~dependencies
        ()
    in

    let sourcePath = Scope.SandboxPath.ofPath sandbox.cfg.buildCfg location in

    let sandboxEnv =
      let f {BuildEnv. name; value} =
        Scope.SandboxEnvironment.Bindings.value name (Scope.SandboxValue.v value)
      in
      List.map ~f (StringMap.values sandbox.sandboxEnv)
    in

    let scope =
      Scope.make
        ~platform:sandbox.platform
        ~sandboxEnv
        ~id
        ~name
        ~version
        ~sourceType
        ~sourcePath
        ~build
        pkg
        buildManifest
    in

    let scope =
      let _seen, scope =
        let f (seen, scope) (direct, _reason, dep) =
          let id = Scope.id dep in
          if BuildId.Set.mem id seen
          then seen, scope
          else
            BuildId.Set.add id seen, Scope.add ~direct ~dep scope
        in
        List.fold_left
          ~f
          ~init:(BuildId.Set.empty, scope)
          dependencies
      in
      if IdS.mem pkg.id matchedForScope
      then Scope.add ~direct:true ~dep:scope scope
      else scope
    in

    let directDependencies =
      PackageId.Set.(elements (remove pkg.Package.id matchedForBuild))
    in

    return (scope, idrepr, directDependencies)
  in

  visit envspec [] id

module Plan = struct

  type t = {
    buildspec : BuildSpec.t;
    tasks : Task.t option PackageId.Map.t;
  }

  let buildspec plan = plan.buildspec

  let get plan id =
    match PackageId.Map.find_opt id plan.tasks with
    | None -> None
    | Some None -> None
    | Some Some task -> Some task

  let findBy plan pred =
    let f (_id, node) = pred node in
    let bindings = PackageId.Map.bindings plan.tasks in
    match List.find_opt ~f bindings with
    | None -> None
    | Some (_id, task) -> task

  let getByName plan name =
    findBy
      plan
      (function
        | None -> false
        | Some task -> String.compare task.Task.pkg.Package.name name = 0)

  let getByNameVersion (plan : t) name version =
    let compare = [%derive.ord: string * Version.t] in
    findBy
      plan
      (function
        | None -> false
        | Some task -> compare (task.Task.pkg.name, task.Task.pkg.version) (name, version) = 0)

  let all plan =
    let f tasks = function
      | _, Some task -> task::tasks
      | _ , None -> tasks
    in
    List.fold_left ~f ~init:[] (PackageId.Map.bindings plan.tasks)
end

let makePlan
  ?(forceImmutable=false)
  buildspec
  mode
  sandbox
  =
  let open Run.Syntax in

  let cache = Hashtbl.create 100 in

  let makeTask pkg =
    match%bind makeScope ~cache ~forceImmutable buildspec mode sandbox pkg.id with
    | None -> return None
    | Some (scope, build, idrepr, dependencies) ->

      let%bind env =
        let%bind bindings = Scope.env ~buildIsInProgress:true ~includeBuildEnv:true scope in
        Run.context
          (Run.ofStringError (Scope.SandboxEnvironment.Bindings.eval bindings))
          "evaluating environment"
      in

      let opamEnv = Scope.toOpamEnv ~buildIsInProgress:true scope in

      let%bind buildCommands =

        let _, commands =
          BuildSpec.classify
            buildspec
            mode
            sandbox.solution
            pkg
            build
        in
        Run.context
          begin match commands with
          | BuildManifest.EsyCommands commands ->
            let%bind commands = renderEsyCommands ~buildIsInProgress:true ~env scope commands in
            let%bind applySubstsCommands = renderOpamSubstsAsCommands opamEnv build.substs in
            let%bind applyPatchesCommands = renderOpamPatchesToCommands opamEnv build.patches in
            return (applySubstsCommands @ applyPatchesCommands @ commands)
          | OpamCommands commands ->
            let%bind commands = renderOpamCommands opamEnv commands in
            let%bind applySubstsCommands = renderOpamSubstsAsCommands opamEnv build.substs in
            let%bind applyPatchesCommands = renderOpamPatchesToCommands opamEnv build.patches in
            return (applySubstsCommands @ applyPatchesCommands @ commands)
          | NoCommands ->
            return []
          end
          "processing build commands"
      in

      let%bind installCommands =
        Run.context
          begin match build.BuildManifest.install with
          | EsyCommands commands ->
            let%bind cmds = renderEsyCommands ~buildIsInProgress:true ~env scope commands in
            return (Some cmds)
          | OpamCommands commands ->
            let%bind cmds = renderOpamCommands opamEnv commands in
            return (Some cmds)
          | NoCommands ->
            return None
          end
          "processing esy.install"
      in

      let task = {
        Task.
        idrepr;
        pkg;
        scope;
        build = buildCommands;
        install = installCommands;
        env;
        dependencies;
      } in

      return (Some task)
  in

  let%bind tasks =
    let root = Solution.root sandbox.solution in
    let rec visit tasks = function
      | [] -> return tasks
      | id::ids ->
        begin match PackageId.Map.find_opt id tasks with
        | Some _ -> visit tasks ids
        | None ->
          let pkg = Solution.getExn id sandbox.solution in
          let%bind task =
            Run.contextf
              (makeTask pkg)
              "creating task for %a" Package.pp pkg
          in
          let tasks = PackageId.Map.add id task tasks in
          let ids =
            let deps =
              if PackageId.compare id root.id = 0
              then PackageId.Set.union pkg.Package.dependencies pkg.Package.devDependencies
              else pkg.Package.dependencies
            in
            PackageId.Set.elements deps @ ids
          in
          visit tasks ids
        end
    in
    visit PackageId.Map.empty [root.id]
  in

  return {Plan. tasks; buildspec;}

let task buildspec mode sandbox id =
  let open RunAsync.Syntax in
  let%bind tasks = RunAsync.ofRun (makePlan buildspec mode sandbox) in
  match Plan.get tasks id with
  | None -> errorf "no build found for %a" PackageId.pp id
  | Some task -> return task

let buildShell buildspec mode sandbox id =
  let open RunAsync.Syntax in
  let%bind task = task buildspec mode sandbox id in
  let plan = Task.plan task in
  EsyBuildPackageApi.buildShell ~cfg:sandbox.cfg plan

module EsyIntrospectionEnv = struct
  let rootPackageConfigPath = "ESY__ROOT_PACKAGE_CONFIG_PATH"
end

let augmentEnvWithOptions (envspec : EnvSpec.t) sandbox scope =
  let open Run.Syntax in

  let {
    EnvSpec.
    augmentDeps;
    buildIsInProgress;
    includeCurrentEnv;
    includeBuildEnv;
    includeEsyIntrospectionEnv;
    includeNpmBin;
  } = envspec in

  let module Env = Scope.SandboxEnvironment.Bindings in
  let module Val = Scope.SandboxValue in

  let%bind env =
    let scope =
      if includeCurrentEnv
      then
        scope
        |> Scope.exposeUserEnvWith Env.value "SHELL"
      else scope
    in
    Scope.env
      ~includeBuildEnv
      ~buildIsInProgress
      scope
  in
  let env =
    if includeNpmBin
    then
      let npmBin = Path.show (EsyInstall.SandboxSpec.binPath sandbox.cfg.spec) in
      Env.prefixValue "PATH" (Val.v npmBin)
      ::env
    else env
  in
  let env =
    if includeCurrentEnv
    then Env.current @ env
    else env
  in

  let env =
    if includeEsyIntrospectionEnv
    then
      match rootPackageConfigPath sandbox with
      | None -> env
      | Some path ->
        Env.value
          EsyIntrospectionEnv.rootPackageConfigPath
          (Val.v (Path.show path))
        ::env
    else env
  in

  let env =
    (* if envspec's DEPSPEC expression was provided we need to filter out env
     * bindings according to it. *)
    match augmentDeps with
    | None -> env
    | Some depspec ->
      let matched =
        DepSpec.collect
          sandbox.solution
          depspec
          (Scope.pkg scope).id
      in
      let matched =
        matched
        |> PackageId.Set.elements
        |> List.map ~f:PackageId.show
        |> StringSet.of_list
      in
      let f binding =
        match Environment.Binding.origin binding with
        | None -> true
        | Some pkgid -> StringSet.mem pkgid matched
      in
      List.filter ~f env
  in

  return (env, scope)

let configure
  ?(forceImmutable=false)
  envspec
  buildspec
  mode
  sandbox
  id
  =
  let open Run.Syntax in
  let cache = Hashtbl.create 100 in

  let%bind scope =
    let scope =
      makeScope
        ~cache
        ~forceImmutable
        ?envspec:envspec.augmentDeps
        buildspec
        mode
        sandbox
        id
    in
    match%bind scope with
    | None -> errorf "no build found for %a" PackageId.pp id
    | Some (scope, _, _, _) -> return scope
  in

  augmentEnvWithOptions envspec sandbox scope

let env ?forceImmutable envspec buildspec mode sandbox id =
  let open Run.Syntax in
  let%map env, _scope = configure ?forceImmutable envspec buildspec mode sandbox id in
  env

let exec
  envspec
  buildspec
  mode
  sandbox
  id
  cmd =
  let open RunAsync.Syntax in
  let%bind env, scope = RunAsync.ofRun (
    let open Run.Syntax in
    let%bind env, scope = configure envspec buildspec mode sandbox id in
    let%bind env = Run.ofStringError (Scope.SandboxEnvironment.Bindings.eval env) in
    return (env, scope)
  ) in

  let%bind cmd = RunAsync.ofRun (
    let open Run.Syntax in

    let expand v =
      let%bind v = Scope.render ~env ~buildIsInProgress:envspec.EnvSpec.buildIsInProgress scope v in
      return (Scope.SandboxValue.render sandbox.cfg.buildCfg v)
    in
    let tool, args = Cmd.getToolAndArgs cmd in
    let%bind tool = expand tool in
    let%bind args = Result.List.map ~f:expand args in
    return (Cmd.ofToolAndArgs (tool, args))
  ) in

  if envspec.EnvSpec.buildIsInProgress
  then
    let%bind task = task buildspec mode sandbox id in
    let plan = Task.plan ~env task in
    EsyBuildPackageApi.buildExec ~cfg:sandbox.cfg plan cmd
  else
    let waitForProcess process =
      let%lwt status = process#status in
      return status
    in
    let env = Scope.SandboxEnvironment.render sandbox.cfg.buildCfg env in
    (* TODO: make sure we resolve 'esy' to the current executable, needed nested
     * invokations *)
    ChildProcess.withProcess
      ~env:(CustomEnv env)
      ~resolveProgramInEnv:true
      ~stderr:(`FD_copy Unix.stderr)
      ~stdout:(`FD_copy Unix.stdout)
      ~stdin:(`FD_copy Unix.stdin)
      cmd
      waitForProcess

let findMaxModifyTime path =
  let open RunAsync.Syntax in
  let skipTraverse path =
    match Path.basename path with
    | "node_modules"
    | ".git"
    | ".hg"
    | ".svn"
    | ".merlin"
    | "esy.lock"
    | "_esy"
    | "_release"
    | "_build"
    | "_install" -> true
    | _ ->
      begin match Path.getExt path with
      (* dune can touch this *)
      | ".install" -> true
      | _ -> false
      end
  in
  let f (prevpath, prevmtime) path stat =
    return (
      let mtime = stat.Unix.st_mtime in
      if mtime > prevmtime
      then path, mtime
      else prevpath, prevmtime
    )
  in
  let label = Printf.sprintf "computing mtime for %s" (Path.show path) in
  Perf.measureLwt ~label (fun () ->
    let%bind path, mtime = Fs.fold ~skipTraverse ~f ~init:(path, 0.0) path in
    return (path, BuildInfo.ModTime.v mtime)
  )

module Changes = struct
  type t =
    | Yes
    | No

  let (+) a b =
    match a, b with
    | No, No -> No
    | _ -> Yes

  let pp fmt = function
    | Yes -> Fmt.unit "yes" fmt ()
    | No -> Fmt.unit "no" fmt ()
end

let isBuilt sandbox task = Fs.exists (Task.installPath sandbox.cfg task)

let buildTask ?quiet ?buildOnly ?logPath sandbox task =
  Logs_lwt.debug (fun m -> m "build %a" Task.pp task);%lwt
  let plan = Task.plan task in
  let label = Fmt.strf "build %a" Task.pp task in
  Perf.measureLwt ~label (fun () ->
    EsyBuildPackageApi.build ?quiet ?buildOnly ?logPath ~cfg:sandbox.cfg plan)

let buildOnly ~force ?quiet ?buildOnly ?logPath sandbox plan id =
  let open RunAsync.Syntax in
  match Plan.get plan id with
  | Some task ->
    if not force
    then
      if%bind isBuilt sandbox task
      then return ()
      else buildTask ?quiet ?buildOnly ?logPath sandbox task
    else buildTask ?quiet ?buildOnly ?logPath sandbox task
  | None -> RunAsync.return ()

let buildRoot ?quiet ?buildOnly sandbox plan =
  let open RunAsync.Syntax in
  let root = Solution.root sandbox.solution in
  match Plan.get plan root.id with
  | Some task ->
    let%bind () = buildTask ?quiet ?buildOnly sandbox task in
    let%bind () =
      let buildPath = Task.buildPath sandbox.cfg task in
      let buildPathLink = EsyInstall.SandboxSpec.buildPath sandbox.cfg.Config.spec in
      match System.Platform.host with
      | Windows -> return ()
      | _ -> Fs.symlink ~force:true ~src:buildPath buildPathLink
    in
    return ()
  | None -> RunAsync.return ()

let build' ~concurrency ~buildLinked sandbox plan ids =
  let open RunAsync.Syntax in
  Logs_lwt.debug (fun m -> m "buildDependencies ~concurrency:%i" concurrency);%lwt

  let findMaxModifyTimeMem =
    let mem = Memoize.make () in
    fun path -> Memoize.compute mem path (fun () -> findMaxModifyTime path)
  in

  let checkFreshModifyTime infoPath sourcePath =
    let open RunAsync.Syntax in

    let prevmtime =
      Lwt.catch
        (fun () ->
          match%bind BuildInfo.ofFile infoPath with
          | Some info -> return info.BuildInfo.sourceModTime
          | None -> return None)
        (fun _exn -> return None)
    in

    let%bind mpath, mtime = findMaxModifyTimeMem sourcePath in
    match%bind prevmtime with
    | None ->
      Logs_lwt.debug (fun m -> m "no mtime info found: %a" Path.pp mpath);%lwt
      return (Changes.Yes, mtime)
    | Some prevmtime ->
      if not (BuildInfo.ModTime.equal mtime prevmtime)
      then (
        Logs_lwt.debug (fun m ->
          m "path changed: %a %a (prev %a)"
          Path.pp mpath
          BuildInfo.ModTime.pp mtime
          BuildInfo.ModTime.pp prevmtime
        );%lwt
        return (Changes.Yes, mtime)
      )
      else
        return (Changes.No, mtime)
  in

  let queue = LwtTaskQueue.create ~concurrency () in

  let run ~quiet task () =
    let start = Unix.gettimeofday () in
    if not quiet
    then Logs_lwt.app (fun m -> m "building %a" Task.pp task)
    else Lwt.return ();%lwt
    let logPath = Task.logPath sandbox.cfg task in
    let%bind () = buildTask ~logPath sandbox task in
    if not quiet
    then Logs_lwt.app (fun m -> m "building %a: done" Task.pp task)
    else Lwt.return ();%lwt
    let stop = Unix.gettimeofday () in
    return (stop -. start)
  in

  let runIfNeeded changesInDependencies task =
    let infoPath = Task.buildInfoPath sandbox.cfg task in
    let sourcePath = Task.sourcePath sandbox.cfg task in
    let%bind isBuilt = isBuilt sandbox task in
    match Scope.sourceType task.scope with
    | SourceType.Transient ->
      let%bind changesInSources, mtime = checkFreshModifyTime infoPath sourcePath in
      begin match isBuilt, Changes.(changesInDependencies + changesInSources) with
      | true, Changes.No ->
        Logs_lwt.debug (fun m ->
          m "building %a: skipping (changesInDependencies: %a, changesInSources: %a)"
          Task.pp task Changes.pp changesInDependencies Changes.pp changesInSources
        );%lwt
        return Changes.No
      | true, Changes.Yes
      | false, _ ->
        let%bind timeSpent = LwtTaskQueue.submit queue (run ~quiet:false task) in
        let%bind () = BuildInfo.toFile infoPath {
          BuildInfo.
          idInfo = task.idrepr;
          timeSpent;
          sourceModTime = Some mtime;
        } in
        return Changes.Yes
      end
    | SourceType.ImmutableWithTransientDependencies ->
      begin match isBuilt, changesInDependencies with
      | true, Changes.No ->
        Logs_lwt.debug (fun m ->
          m "building %a: skipping (changesInDependencies: %a)"
          Task.pp task Changes.pp changesInDependencies
        );%lwt
        return Changes.No
      | true, Changes.Yes
      | false, _ ->
        let%bind timeSpent = LwtTaskQueue.submit queue (run ~quiet:false task) in
        let%bind () = BuildInfo.toFile infoPath {
          BuildInfo.
          idInfo = task.idrepr;
          timeSpent;
          sourceModTime = None;
        } in
        return Changes.Yes
      end
    | SourceType.Immutable ->
      if isBuilt
      then return Changes.No
      else
        let%bind timeSpent = LwtTaskQueue.submit queue (run ~quiet:false task) in
        let%bind () = BuildInfo.toFile infoPath {
          BuildInfo.
          idInfo = task.idrepr;
          timeSpent;
          sourceModTime = None;
        } in
        return Changes.No
  in

  let tasksInProcess = Hashtbl.create 100 in

  let rec process pkg =
    let id = pkg.Package.id in
    match Hashtbl.find_opt tasksInProcess id with
    | None ->
      let running =
        match Plan.get plan id with
        | Some task ->
          let dependencies =
            List.map ~f:(fun id -> Solution.getExn id sandbox.solution)
            task.dependencies
          in
          let%bind changes = processMany dependencies in
          begin match buildLinked, task.Task.pkg.source with
          | false, Link _ -> return changes
          | _, _ ->
            RunAsync.contextf
              (runIfNeeded changes task)
              "building %a" PackageId.ppNoHash id
          end
        | None -> RunAsync.return Changes.No
      in
      Hashtbl.replace tasksInProcess id running;
      running
    | Some running -> running
  and processMany dependencies =
    let%bind changes = RunAsync.List.mapAndJoin ~f:process dependencies in
    let changes = List.fold_left ~f:Changes.(+) ~init:Changes.No changes in
    return changes
  in

  let%bind pkgs = RunAsync.ofRun (
    let open Run.Syntax in
    let f id =
      match Solution.get id sandbox.solution with
      | None -> Run.errorf "no such package %a" PackageId.pp id
      | Some pkg -> return pkg
    in
    Result.List.map ~f ids
  ) in

  let%bind _ : Changes.t = processMany pkgs in
  return ()

let build ?(concurrency=1) ~buildLinked sandbox plan ids =
  Perf.measureLwt
    ~label:"build"
    (fun () -> build' ~concurrency ~buildLinked sandbox plan ids)

let exportBuild ~cfg ~outputPrefixPath buildPath =
  let open RunAsync.Syntax in
  let buildId = Path.basename buildPath in
  let%lwt () = Logs_lwt.app (fun m -> m "Exporting %s" buildId) in
  let outputPath = Path.(outputPrefixPath / Printf.sprintf "%s.tar.gz" buildId) in
  let%bind origPrefix, destPrefix =
    let%bind prevStorePrefix = Fs.readFile Path.(buildPath / "_esy" / "storePrefix") in
    let nextStorePrefix = String.make (String.length prevStorePrefix) '_' in
    return (Path.v prevStorePrefix, Path.v nextStorePrefix)
  in
  let%bind stagePath =
    let path = Path.(cfg.Config.buildCfg.storePath / "s" / buildId) in
    let%bind () = Fs.rmPath path in
    let%bind () = Fs.copyPath ~src:buildPath ~dst:path in
    return path
  in
  let%bind () = RewritePrefix.rewritePrefix ~origPrefix ~destPrefix stagePath in
  let%bind () = Fs.createDir (Path.parent outputPath) in
  let%bind () =
    Tarball.create ~filename:outputPath ~outpath:buildId (Path.parent stagePath)
  in
  let%lwt () = Logs_lwt.app (fun m -> m "Exporting %s: done" buildId) in
  let%bind () = Fs.rmPath stagePath in
  return ()

let importBuild ~cfg buildPath =
  let open RunAsync.Syntax in
  let buildId, kind =
    if Path.hasExt "tar.gz" buildPath
    then
      (buildPath |> Path.remExt |> Path.remExt |> Path.basename, `Archive)
    else
      (buildPath |> Path.basename, `Dir)
  in
  let%lwt () = Logs_lwt.app (fun m -> m "Import %s" buildId) in
  let outputPath = Path.(cfg.Config.buildCfg.storePath / Store.installTree / buildId) in
  if%bind Fs.exists outputPath
  then (
    let%lwt () = Logs_lwt.app (fun m -> m "Import %s: already in store, skipping..." buildId) in
    return ()
  ) else
    let importFromDir buildPath =
      let%bind origPrefix =
        let%bind v = Fs.readFile Path.(buildPath / "_esy" / "storePrefix") in
        return (Path.v v)
      in
      let%bind () = RewritePrefix.rewritePrefix ~origPrefix ~destPrefix:cfg.buildCfg.storePath buildPath in
      let%bind () = Fs.rename ~src:buildPath outputPath in
      let%lwt () = Logs_lwt.app (fun m -> m "Import %s: done" buildId) in
      return ()
    in
    match kind with
    | `Dir ->
      let%bind stagePath =
        let path = Path.(cfg.buildCfg.storePath / "s" / buildId) in
        let%bind () = Fs.rmPath path in
        let%bind () = Fs.copyPath ~src:buildPath ~dst:path in
        return path
      in
      importFromDir stagePath
    | `Archive ->
      let stagePath = Path.(cfg.buildCfg.storePath / Store.stageTree / buildId) in
      let%bind () =
        let cmd = Cmd.(
          v "tar"
          % "-C" % p (Path.parent stagePath)
          % "-xz"
          % "-f" % p buildPath
        ) in
        ChildProcess.run cmd
      in
      importFromDir stagePath
