module Solution = EsyInstall.Solution
module PackageId = EsyInstall.PackageId
module Overrides = EsyInstall.Package.Overrides
module Package = EsyInstall.Solution.Package
module Installation = EsyInstall.Installation
module Source = EsyInstall.Source
module Version = EsyInstall.Version

type t = {
  cfg : Config.t;
  platform : System.Platform.t;
  sandboxEnv : BuildManifest.Env.t;
  solution : EsyInstall.Solution.t;
  installation : EsyInstall.Installation.t;
  manifests : BuildManifest.t PackageId.Map.t;
}

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
        BuildManifest.ofInstallationLocation
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
  ?(platform=System.Platform.host)
  ?(sandboxEnv=BuildManifest.Env.empty)
  cfg
  solution
  installation =
  let open RunAsync.Syntax in
  let%bind paths, manifests = readManifests cfg solution installation in
  return ({
    cfg;
    platform;
    sandboxEnv;
    solution;
    installation;
    manifests;
  }, paths)


let renderExpression sandbox scope expr =
  let open Run.Syntax in
  let%bind expr = Scope.render ~buildIsInProgress:false scope expr in
  return (Scope.SandboxValue.render sandbox.cfg.buildCfg expr)

module DepSpec = struct

  module Id = struct
    type t =
      | Self
      | Root
      [@@deriving ord]

    let pp fmt = function
      | Self -> Fmt.unit "self" fmt ()
      | Root -> Fmt.unit "root" fmt ()
  end

  include EsyInstall.DepSpec.Make(Id)

  let root = Id.Root
  let self = Id.Self

  let resolve solution self id =
    match id with
    | Id.Root -> (Solution.root solution).id
    | Id.Self -> self

  let eval solution self depspec =
    let resolve id = resolve solution self id in
    let rec eval' expr =
      match expr with
      | Package id -> PackageId.Set.singleton (resolve id)
      | Dependencies id ->
        let pkg = Solution.getExn (resolve id) solution in
        pkg.dependencies
      | DevDependencies id ->
        let pkg = Solution.getExn (resolve id) solution in
        pkg.devDependencies
      | Union (a, b) -> PackageId.Set.union (eval' a) (eval' b)
    in
    eval' depspec

end

module EnvSpec = struct
  type t = {
    augmentDeps : DepSpec.t option;
    buildIsInProgress : bool;
    includeCurrentEnv : bool;
    includeBuildEnv : bool;
    includeNpmBin : bool;
  }
end

module BuildSpec = struct
  type t = {
    buildLinked : build option;
    buildAll : build;
  }

  and build = {
    mode : mode;
    deps : DepSpec.t;
  }

  and mode =
    | Build
    | BuildDev

  let pp_mode fmt = function
    | Build -> Fmt.string fmt "build"
    | BuildDev -> Fmt.string fmt "buildDev"

  let classify spec pkg =
    match pkg.Package.source, spec.buildLinked with
    | Install _, _ -> spec.buildAll
    | Link _, None -> spec.buildAll
    | Link _, Some buildLinked -> buildLinked

end

module Task = struct
  type t = {
    pkg : Package.t;
    scope : Scope.t;
    env : Scope.SandboxEnvironment.t;
    build : Scope.SandboxValue.t list list;
    install : Scope.SandboxValue.t list list option;
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
      id = Scope.id t.scope;
      name = t.pkg.name;
      version = EsyInstall.Version.show t.pkg.version;
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
    | BuildManifest.Command.Parsed args ->
      let f arg =
        let%bind arg = renderArg arg in
        return (Scope.SandboxValue.v arg)
      in
      Result.List.map ~f args
    | BuildManifest.Command.Unparsed line ->
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

let buildId ~commands ~sandboxEnv ~id ~dist ~build ~dependencies () =

  let hash =

    (* include ids of dependencies *)
    let dependencies =
      let f = function
        | true, dep -> Some ("dep:" ^ Scope.id dep)
        | false, _ -> None
      in
      dependencies
      |> List.map ~f
      |> List.filterNone
      |> List.sort ~cmp:String.compare
    in

    (* include parts of the current package metadata which contribute to the
      * build commands/environment *)
    let self =
      build
      |> BuildManifest.to_yojson
      |> Yojson.Safe.to_string
    in

    let commands =
      commands
      |> BuildManifest.commands_to_yojson
      |> Yojson.Safe.to_string
    in

    (* a special tag which is communicated by the installer and specifies
      * the version of distribution of vcs commit sha *)
    let dist =
      match dist with
      | Some dist -> EsyInstall.Dist.show dist
      | None -> "-"
    in

    let sandboxEnv =
      sandboxEnv
      |> BuildManifest.Env.to_yojson
      |> Yojson.Safe.to_string
    in

    String.concat "__" ((PackageId.show id)::sandboxEnv::dist::self::commands::dependencies)
    |> Digest.string
    |> Digest.to_hex
    |> fun hash -> String.sub hash 0 8
  in

  let name = PackageId.name id in
  let version = PackageId.version id in

  match version with
  | Version.Npm _
  | Version.Opam _ ->
    Printf.sprintf "%s-%s-%s"
      (Path.safeSeg name)
      (Path.safePath (Version.show version))
      hash
  | Version.Source _ ->
    Printf.sprintf "%s-%s"
      (Path.safeSeg name)
      hash

let makeScope
  ?cache
  ~forceImmutable
  buildspec
  sandbox
  id
  =
  let open Run.Syntax in

  Logs.debug (fun m -> m "makeScope %a" PackageId.pp id);

  let updateSeen seen id =
    match List.find_opt ~f:(fun p -> PackageId.compare p id = 0) seen with
    | Some _ -> errorf "@[<h>found circular dependency on: %a@]" PackageId.pp id
    | None -> return (id::seen)
  in

  let cache =
    match cache with
    | None -> Hashtbl.create 100
    | Some cache -> cache
  in

  let rec visit seen (id : PackageId.t) =
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
            let%bind scope = visit' seen id build in
            return (Some (scope, build))
          ) "processing %a" PackageId.pp id
        | None -> return None
      in
      Hashtbl.replace cache id res;
      return res

  and visit' seen id build =
    let pkg = Solution.getExn id sandbox.solution in
    let location = Installation.findExn id sandbox.installation in

    let {BuildSpec. mode; deps} = BuildSpec.classify buildspec pkg in

    let matched =
      DepSpec.eval sandbox.solution pkg.Package.id deps
    in
    Logs.debug (fun m ->
      m "depspec %a at %a matches %a"
        DepSpec.pp
        deps
        PackageId.pp
        pkg.Package.id
        Fmt.(list ~sep:(unit ", ") PackageId.pp)
        (PackageId.Set.elements matched)
    );

    let%bind dependencies =
      let dependencies =
        (* remove self here so we don't call into itself *)
        PackageId.Set.(elements (remove pkg.Package.id matched))
      in
      let collect dependencies (direct, pkg) =
        match%bind visit seen pkg.Package.id with
        | Some (scope, _build) ->
          return ((direct, scope)::dependencies)
        | None -> return dependencies
      in
      Result.List.foldLeft
        ~f:collect
        ~init:[]
        (Solution.allDependenciesBFS ~dependencies id sandbox.solution)
    in

    let dist, sourceType =
      match pkg.source with
      | Install info ->
        let hasTransientDeps =
          let f (_direct, scope) = Scope.sourceType scope = SourceType.Transient in
          List.exists ~f dependencies
        in
        let dist, _ = info.source in
        let sourceType =
          if hasTransientDeps
          then SourceType.ImmutableWithTransientDependencies
          else SourceType.Immutable
        in
        Some dist, sourceType
      | Link _ ->
        None, SourceType.Transient
    in
    let sourceType =
      if forceImmutable
      then SourceType.Immutable
      else sourceType
    in

    let name = PackageId.name id in
    let version = PackageId.version id in

    let commands =
      match mode, sourceType, build.BuildManifest.buildDev with
      | BuildSpec.Build, _, _
      | BuildSpec.BuildDev, (ImmutableWithTransientDependencies | Immutable), _
      | BuildSpec.BuildDev, Transient, None -> build.BuildManifest.build
      | BuildSpec.BuildDev, Transient, Some commands -> BuildManifest.EsyCommands commands
    in

    let id =
      buildId
        ~commands
        ~sandboxEnv:sandbox.sandboxEnv
        ~id:pkg.id
        ~dist
        ~build
        ~dependencies
        ()
    in

    let sourcePath = Scope.SandboxPath.ofPath sandbox.cfg.buildCfg location in

    let sandboxEnv =
      let f {BuildManifest.Env. name; value} =
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
        pkg
        build
    in

    let _, scope =
      let f (seen, scope) (direct, dep) =
        let id = Scope.id dep in
        if StringSet.mem id seen
        then seen, scope
        else
          let pkg = Scope.pkg dep in
          match direct, PackageId.Set.mem pkg.id matched with
          | true, false -> seen, scope
          | true, true
          | false, _ ->
            StringSet.add id seen,
            Scope.add ~direct ~dep scope
      in
      List.fold_left
        ~f
        ~init:(StringSet.empty, scope)
        (dependencies @ [true, scope])
    in

    return scope
  in

  visit [] id

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

  let findByPred plan pred =
    let f id =
      let task = PackageId.Map.find id plan.tasks in
      pred task
    in
    match PackageId.Map.find_first_opt f plan.tasks with
    | None -> None
    | Some (_id, task) -> task

  let getByName plan name =
    findByPred
      plan
      (function
        | None -> false
        | Some task -> String.compare task.Task.pkg.Solution.Package.name name >= 0)

  let getByNameVersion (plan : t) name version =
    let compare = [%derive.ord: string * Version.t] in
    findByPred
      plan
      (function
        | None -> false
        | Some task -> compare (task.Task.pkg.name, task.Task.pkg.version) (name, version) >= 0)

  let all plan =
    let f tasks = function
      | _, Some task -> task::tasks
      | _ , None -> tasks
    in
    List.fold_left ~f ~init:[] (PackageId.Map.bindings plan.tasks)
end

let makePlan
  ?(forceImmutable=false)
  sandbox
  buildspec
  =
  let open Run.Syntax in

  let cache = Hashtbl.create 100 in

  let makeTask pkg =
    match%bind makeScope ~cache ~forceImmutable buildspec sandbox pkg.id with
    | None -> return None
    | Some (scope, build) ->

      let%bind env =
        let%bind bindings = Scope.env ~buildIsInProgress:true ~includeBuildEnv:true scope in
        Run.context
          (Run.ofStringError (Scope.SandboxEnvironment.Bindings.eval bindings))
          "evaluating environment"
      in

      let opamEnv = Scope.toOpamEnv ~buildIsInProgress:true scope in

      let%bind buildCommands =

        let {BuildSpec. mode; deps = _;} = BuildSpec.classify buildspec pkg in
        match mode, Scope.sourceType scope, build.BuildManifest.buildDev with
        | BuildSpec.Build, _, _
        | BuildDev, (ImmutableWithTransientDependencies | Immutable), _
        | BuildDev, Transient, None ->
          Run.context
            begin match build.BuildManifest.build with
            | EsyCommands commands ->
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
            "processing esy.build"
        | BuildSpec.BuildDev, Transient, Some commands ->
          Run.context (
            let%bind commands = renderEsyCommands ~buildIsInProgress:true ~env scope commands in
            let%bind applySubstsCommands = renderOpamSubstsAsCommands opamEnv build.substs in
            let%bind applyPatchesCommands = renderOpamPatchesToCommands opamEnv build.patches in
            return (applySubstsCommands @ applyPatchesCommands @ commands)
          ) "processing esy.buildDev"
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
        pkg;
        scope;
        build = buildCommands;
        install = installCommands;
        env;
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
              "processing %a" Package.pp pkg
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

let task buildspec sandbox id =
  let open RunAsync.Syntax in
  let%bind tasks = RunAsync.ofRun (makePlan sandbox buildspec) in
  match Plan.get tasks id with
  | None -> errorf "no build found for %a" PackageId.pp id
  | Some task -> return task

let buildShell buildspec sandbox id =
  let open RunAsync.Syntax in
  let%bind task = task buildspec sandbox id in
  let plan = Task.plan task in
  EsyBuildPackageApi.buildShell ~cfg:sandbox.cfg plan

let makeEnv
  ?cache
  ~forceImmutable
  envspec
  buildspec
  sandbox
  scope
  =
  let open Run.Syntax in
  let pkg = Scope.pkg scope in
  let envdepspec =
    let {BuildSpec. deps; mode = _;} = BuildSpec.classify buildspec pkg in
    Option.orDefault
      ~default:deps
      envspec.EnvSpec.augmentDeps
  in
  let matched = DepSpec.eval sandbox.solution pkg.id envdepspec in
  Logs.debug (fun m ->
    m "envspec %a at %a matches %a"
      DepSpec.pp
      envdepspec
      PackageId.pp
      pkg.id
      Fmt.(list ~sep:(unit ", ") PackageId.pp)
      (PackageId.Set.elements matched)
  );

  let makeScope id =
    match%bind makeScope ?cache ~forceImmutable buildspec sandbox id with
    | None -> return None
    | Some (scope, _build) -> return (Some scope)
  in

  let dependencies =
    let dependencies = PackageId.Set.(elements (remove pkg.id matched)) in
    Solution.allDependenciesBFS
      ~dependencies
      pkg.id
      sandbox.solution
  in

  let%bind scope =
    let collect scope (_direct, pkg) =
      if PackageId.Set.mem pkg.Package.id matched
      then
        match%bind makeScope pkg.Package.id with
        | None -> return scope
        | Some dep -> return (Scope.add ~direct:true ~dep scope)
      else
        return scope
    in
    Run.List.foldLeft
      ~f:collect
      ~init:scope
      (dependencies @ [true, Solution.getExn pkg.id sandbox.solution])
  in

  let%bind env =
    let scope =
      if envspec.EnvSpec.includeCurrentEnv
      then
        scope
        |> Scope.exposeUserEnvWith Scope.SandboxEnvironment.Bindings.value "SHELL"
      else scope
    in
    Scope.env
      ~includeBuildEnv:envspec.includeBuildEnv
      ~buildIsInProgress:envspec.buildIsInProgress
      scope
  in
  let env =
    if envspec.includeNpmBin
    then
      let npmBin = Path.show (EsyInstall.SandboxSpec.binPath sandbox.cfg.spec) in
      Scope.SandboxEnvironment.Bindings.prefixValue
        "PATH"
        (Scope.SandboxValue.v npmBin)
      ::env
    else env
  in
  let env =
    if envspec.includeCurrentEnv
    then Scope.SandboxEnvironment.Bindings.current @ env
    else env
  in
  return (env, scope)

let configure
  ?(forceImmutable=false)
  envspec
  buildspec
  sandbox
  id
  =
  let open Run.Syntax in
  let cache = Hashtbl.create 100 in

  let%bind scope =
    match%bind makeScope ~cache ~forceImmutable buildspec sandbox id with
    | None -> errorf "no build found for %a" PackageId.pp id
    | Some (scope, _) -> return scope
  in

  makeEnv
    ~cache
    ~forceImmutable
    envspec
    buildspec
    sandbox
    scope

let env ?forceImmutable envspec buildspec sandbox id =
  let open Run.Syntax in
  let%map env, _scope = configure ?forceImmutable envspec buildspec sandbox id in
  env

let exec
  envspec
  buildspec
  sandbox
  id
  cmd =
  let open RunAsync.Syntax in
  let%bind task = task buildspec sandbox id in
  let%bind env, scope = RunAsync.ofRun (
    let open Run.Syntax in
    let%bind env, scope =
      makeEnv
        ~forceImmutable:false
        envspec
        buildspec
        sandbox
        task.Task.scope
    in
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
  Perf.measureLwt ~label (fun () -> Fs.fold ~skipTraverse ~f ~init:(path, 0.0) path)

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

let build ~force ?quiet ?buildOnly ?logPath sandbox plan id =
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

let buildDependencies' ~concurrency ~buildLinked sandbox plan id =
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
      if mtime > prevmtime
      then (
        Logs_lwt.debug (fun m -> m "path changed: %a %f" Path.pp mpath mtime);%lwt
        return (Changes.Yes, mtime)
      )
      else
        return (Changes.No, mtime)
  in

  let queue = LwtTaskQueue.create ~concurrency () in
  let root = Solution.root sandbox.solution in

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
          timeSpent;
          sourceModTime = None;
        } in
        return Changes.No
  in

  let tasksInProcess = Hashtbl.create 100 in

  let rec process pkg =
    let id = pkg.Solution.Package.id in
    match Hashtbl.find_opt tasksInProcess id with
    | None ->
      let running =
        match Plan.get plan id with
        | Some task ->
          let%bind changes = processDependencies pkg in
          begin match buildLinked, task.Task.pkg.source with
          | false, Link _ -> return changes
          | _, _ ->
            RunAsync.contextf
              (runIfNeeded changes task)
              "building %a" PackageId.pp id
          end
        | None -> RunAsync.return Changes.No
      in
      Hashtbl.replace tasksInProcess id running;
      running
    | Some running -> running
  and processDependencies pkg =
    let dependencies =
      let traverse =
        if Package.compare root pkg = 0
        then Solution.traverseWithDevDependencies
        else Solution.traverse
      in
      Solution.dependencies ~traverse pkg sandbox.solution
    in
    let%bind changes = RunAsync.List.mapAndJoin ~f:process dependencies in
    let changes = List.fold_left ~f:Changes.(+) ~init:Changes.No changes in
    return changes
  in

  match Solution.get id sandbox.solution with
  | None -> RunAsync.errorf "no such package %a" PackageId.pp id
  | Some pkg ->
    let%bind _: Changes.t = processDependencies pkg in
    return ()

let buildDependencies ?(concurrency=1) ~buildLinked sandbox plan id =
  Perf.measureLwt
    ~label:"buildDependencies"
    (fun () -> buildDependencies' ~concurrency ~buildLinked sandbox plan id)

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
