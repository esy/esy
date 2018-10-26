module Solution = EsyInstall.Solution
module PackageId = EsyInstall.PackageId
module Overrides = EsyInstall.Package.Overrides
module Package = EsyInstall.Solution.Package
module Installation = EsyInstall.Installation
module Source = EsyInstall.Source
module Version = EsyInstall.Version

module Task = struct
  type t = {
    id : string;
    pkgId : PackageId.t;
    name : string;
    version : Version.t;
    env : Scope.SandboxEnvironment.t;
    buildCommands : Scope.SandboxValue.t list list;
    installCommands : Scope.SandboxValue.t list list;
    buildType : BuildManifest.BuildType.t;
    sourceType : BuildManifest.SourceType.t;
    sourcePath : Scope.SandboxPath.t;
    buildScope : Scope.t;
    exportedScope : Scope.t;
    platform : System.Platform.t;
  }

  let plan (t : t) =
    {
      EsyBuildPackage.Plan.
      id = t.id;
      name = t.name;
      version = EsyInstall.Version.show t.version;
      sourceType = t.sourceType;
      buildType = t.buildType;
      build = t.buildCommands;
      install = t.installCommands;
      sourcePath = Scope.SandboxPath.toValue t.sourcePath;
      env = t.env;
    }

  let to_yojson t = EsyBuildPackage.Plan.to_yojson (plan t)

  let installPath t = Scope.installPath t.exportedScope
  let logPath t = Scope.logPath t.exportedScope

  let renderExpression ~cfg task expr =
    let open Run.Syntax in
    let%bind expr = Scope.renderCommandExpr task.exportedScope expr in
    let expr = Scope.SandboxValue.v expr in
    let expr = Scope.SandboxValue.render cfg.Config.buildCfg expr in
    return expr

end

type t = {
  tasks : Task.t option PackageId.Map.t;
  solution : Solution.t;
}

let toOCamlVersion version =
  let version = Version.showSimple version in
  match String.split_on_char '.' version with
  | major::minor::patch::[] ->
    let patch =
      let v = try int_of_string patch with _ -> 0 in
      if v < 1000 then v else v / 1000
    in
    major ^ ".0" ^ minor ^ "." ^ (string_of_int patch)
  | _ -> version

let renderEsyCommands ~env scope commands =
  let open Run.Syntax in
  let envScope name =
    match Scope.SandboxEnvironment.find name env with
    | Some v -> Some (Scope.SandboxValue.show v)
    | None -> None
  in

  let renderArg v =
    let%bind v = Scope.renderCommandExpr scope v in
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

let readManifests ~cfg (solution : Solution.t) (installation : Installation.t) =
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
      | Some manifest -> return (id, Some (manifest, paths))
      | None ->
        if isRoot
        then
          let manifest = BuildManifest.empty ~name:None ~version:None () in
          return (id, Some (manifest, Path.Set.empty))
        else
          return (id, None)
    ) "reading manifest %a" PackageId.pp id
  in

  let%bind items =
    RunAsync.List.mapAndJoin
      ~concurrency:100
      ~f:readManifest
      (Installation.entries installation)
  in

  let paths, manifests =
    let f (paths, manifests) (id, manifest) =
      match manifest with
      | None -> paths, manifests
      | Some (manifest, manifestPaths) ->
        let paths = Path.Set.union paths manifestPaths in
        let manifests = PackageId.Map.add id manifest manifests in
        paths, manifests
    in
    List.fold_left ~f ~init:(Path.Set.empty, PackageId.Map.empty) items
  in

  Logs_lwt.debug (fun m -> m "reading manifests: done");%lwt

  return (paths, manifests)

let buildId ~sandboxEnv ~name ~version build source dependencies =

  let hash =

    (* include ids of dependencies *)
    let dependencies =
      let f dep =
        match dep with
        | _, None -> None
        | false, Some _ -> None
        | true, Some dep -> Some ("dep:" ^ dep.Task.id)
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

    (* a special tag which is communicated by the installer and specifies
      * the version of distribution of vcs commit sha *)
    let source =
      match source with
      | Some source -> BuildManifest.Source.show source
      | None -> "-"
    in

    let sandboxEnv =
      sandboxEnv
      |> BuildManifest.Env.to_yojson
      |> Yojson.Safe.to_string
    in

    String.concat "__" (sandboxEnv::source::self::dependencies)
    |> Digest.string
    |> Digest.to_hex
    |> fun hash -> String.sub hash 0 8
  in

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

let make'
  ?(forceImmutable=false)
  ?(platform=System.Platform.host)
  ~buildCfg
  ~sandboxEnv
  ~solution
  ~installation
  ~manifests
  () =
  let open Run.Syntax in

  let root = Solution.root solution in
  let tasks = ref PackageId.Map.empty in

  let rec aux pkg =
    let id = Package.id pkg in
    match PackageId.Map.find_opt id !tasks with
    | Some None -> return None
    | Some (Some build) -> return (Some build)
    | None ->
      Logs.debug (fun m -> m "plan %a" PackageId.pp id);
      begin match PackageId.Map.find_opt id manifests with
      | Some manifest ->
        let%bind build =
          Run.contextf
            (aux' id pkg manifest)
            "processing %a" PackageId.pp id
        in
        return (Some build)
      | None -> return None
      end

  and aux' pkgId pkg build =
    let location = Installation.findExn pkgId installation in

    let%bind dependencies =
      let f (direct, pkg) =
        let%bind build = aux pkg in
        return (direct, build)
      in
      let traverse =
        if PackageId.compare (Solution.Package.id root) pkgId = 0
        then Solution.traverseWithDevDependencies
        else Solution.traverse
      in
      Result.List.map ~f (Solution.allDependenciesBFS ~traverse pkg solution)
    in

    Logs.debug (fun m ->
      let ppTask fmt task = PackageId.pp fmt task.Task.pkgId in
      let ppDep = Fmt.(pair ~sep:comma bool (option ppTask)) in
      let ppDeps = Fmt.(brackets (list ~sep:(unit "@;") (hbox (brackets ppDep)))) in
      m "plan %a dependencies@[<v 2>@;%a@]"
        PackageId.pp pkgId
        ppDeps dependencies
    );

    let source, sourcePath, sourceType =
      match pkg.source with
      | EsyInstall.Package.Install info ->
        let source, _ = info.source in
        let sourceType =
          let hasTransientDeps =
            let f = function
              | _, Some {Task. sourceType = SourceType.Transient; _} -> true
              | _, _ -> false
            in
            List.exists ~f dependencies
          in
          if hasTransientDeps
          then SourceType.Transient
          else SourceType.Immutable
        in
        Some source, location, sourceType
      | EsyInstall.Package.Link _ ->
        None, location, SourceType.Transient
    in
    let sourceType =
      if forceImmutable
      then SourceType.Immutable
      else sourceType
    in

    let name = PackageId.name pkgId in
    let version = PackageId.version pkgId in
    let id = buildId ~sandboxEnv:BuildManifest.Env.empty ~name ~version build source dependencies in
    let sourcePath = Scope.SandboxPath.ofPath buildCfg sourcePath in

    let exportedScope, buildScope =

      let sandboxEnv =
        let f {BuildManifest.Env. name; value} =
          Scope.SandboxEnvironment.Bindings.value name (Scope.SandboxValue.v value)
        in
        List.map ~f (StringMap.values sandboxEnv)
      in

      let exportedScope =
        Scope.make
          ~platform
          ~sandboxEnv
          ~id
          ~name
          ~version
          ~sourceType
          ~sourcePath
          ~buildIsInProgress:false
          build
      in

      let buildScope =
        Scope.make
          ~platform
          ~sandboxEnv
          ~id
          ~name
          ~version
          ~sourceType
          ~sourcePath
          ~buildIsInProgress:true
          build
      in

      let _, exportedScope, buildScope =
        let f (seen, exportedScope, buildScope) (direct, dep) =
          match dep with
          | None -> (seen, exportedScope, buildScope)
          | Some build ->
            (* don't add dev dependencies to build scope *)
            if PackageId.Set.mem build.Task.pkgId pkg.devDependencies
            then (seen, exportedScope, buildScope)
            else
              if StringSet.mem build.Task.id seen
              then seen, exportedScope, buildScope
              else
                StringSet.add build.Task.id seen,
                Scope.add ~direct ~dep:build.exportedScope exportedScope,
                Scope.add ~direct ~dep:build.exportedScope buildScope
        in
        List.fold_left
          ~f
          ~init:(StringSet.empty, exportedScope, buildScope)
          dependencies
      in

      exportedScope, buildScope
    in

    let%bind buildEnv =
      let%bind bindings = Scope.env ~includeBuildEnv:true buildScope in
      Run.context
        (Run.ofStringError (Scope.SandboxEnvironment.Bindings.eval bindings))
        "evaluating environment"
    in

    let ocamlVersion =
      let open Option.Syntax in
      let%bind _, maybeOcaml =
        let f = function
          | _, Some {Task.name = "ocaml";_ } -> true
          | _, _ -> false
        in
        List.find_opt ~f dependencies
      in
      let%bind ocaml = maybeOcaml in
      return (toOCamlVersion ocaml.Task.version)
    in

    let opamEnv = Scope.toOpamEnv ~ocamlVersion buildScope in

    let%bind buildCommands =
      Run.context
        begin match build.buildCommands with
        | BuildManifest.EsyCommands commands ->
          let%bind commands = renderEsyCommands ~env:buildEnv buildScope commands in
          let%bind applySubstsCommands = renderOpamSubstsAsCommands opamEnv build.substs in
          let%bind applyPatchesCommands = renderOpamPatchesToCommands opamEnv build.patches in
          return (applySubstsCommands @ applyPatchesCommands @ commands)
        | BuildManifest.OpamCommands commands ->
          let%bind commands = renderOpamCommands opamEnv commands in
          let%bind applySubstsCommands = renderOpamSubstsAsCommands opamEnv build.substs in
          let%bind applyPatchesCommands = renderOpamPatchesToCommands opamEnv build.patches in
          return (applySubstsCommands @ applyPatchesCommands @ commands)
        end
        "processing esy.build"
    in

    let%bind installCommands =
      Run.context
        begin match build.installCommands with
        | BuildManifest.EsyCommands commands ->
          renderEsyCommands ~env:buildEnv buildScope commands
        | BuildManifest.OpamCommands commands ->
          renderOpamCommands opamEnv commands
        end
        "processing esy.install"
    in

    let task = {
      Task.
      id;
      pkgId;
      name;
      version;
      buildCommands;
      installCommands;
      env = buildEnv;
      buildType = build.buildType;
      sourceType;
      sourcePath;
      platform;
      exportedScope;
      buildScope;
    } in

    tasks := PackageId.Map.add (Package.id pkg) (Some task) !tasks;

    return task

  in

  let%bind (_ : Task.t option) = aux root in

  return !tasks

let make
  ?forceImmutable
  ?platform
  ~cfg
  ~sandboxEnv
  ~(solution : Solution.t)
  ~(installation : Installation.t) () =
  let open RunAsync.Syntax in
  let%bind files, manifests = readManifests ~cfg solution installation in
  Logs_lwt.debug (fun m -> m "creating plan");%lwt
  let%bind tasks = RunAsync.ofRun (
    make'
      ?forceImmutable
      ?platform
      ~buildCfg:cfg.Config.buildCfg
      ~sandboxEnv
      ~solution
      ~installation
      ~manifests
      ()
  ) in
  Logs_lwt.debug (fun m -> m "creating plan: done");%lwt
  let%bind filesUsed =
    let f path =
      let%bind stats = Fs.stat path in
      let mtime = stats.Unix.st_mtime in
      return {FileInfo. path; mtime}
    in
    files
    |> Path.Set.elements
    |> List.map ~f
    |> RunAsync.List.joinAll
  in
  return ({tasks; solution;}, filesUsed)

let findTaskById plan id =
  match PackageId.Map.find_opt id plan.tasks with
  | None -> Run.errorf "no task found for package %a" PackageId.pp id
  | Some task -> Run.return task

let findTaskByName plan name =
  let f _id pkg =
    String.compare pkg.Solution.Package.name name >= 0
  in
  match Solution.find f plan.solution with
  | None -> None
  | Some (id, _) -> Some (PackageId.Map.find id plan.tasks)

let rootTask plan =
  let id = Solution.Package.id (Solution.root plan.solution) in
  match PackageId.Map.find_opt id plan.tasks with
  | None -> None
  | Some None -> None
  | Some (Some task) -> Some task

let allTasks plan =
  let f tasks = function
    | _, Some task -> task::tasks
    | _ , None -> tasks
  in
  List.fold_left ~f ~init:[] (PackageId.Map.bindings plan.tasks)

let shell ~cfg task =
  let plan = Task.plan task in
  EsyBuildPackageApi.buildShell ~cfg plan

let exec ~cfg task cmd =
  let plan = Task.plan task in
  EsyBuildPackageApi.buildExec ~cfg plan cmd

let buildTask ?force ?quiet ?buildOnly ?logPath ~cfg task =
  Logs_lwt.debug (fun m -> m "build %a" PackageId.pp task.Task.pkgId);%lwt
  let plan = Task.plan task in
  EsyBuildPackageApi.build ?force ?quiet ?buildOnly ?logPath ~cfg plan

let build ?force ?quiet ?buildOnly ?logPath ~cfg plan id =
  match PackageId.Map.find_opt id plan.tasks with
  | Some (Some task) -> buildTask ?force ?quiet ?buildOnly ?logPath ~cfg task
  | Some None
  | None -> RunAsync.return ()

let buildDependencies ?(concurrency=1) ~cfg plan id =
  let open RunAsync.Syntax in
  Logs_lwt.debug (fun m -> m "buildDependencies ~concurrency:%i" concurrency);%lwt

  let queue = LwtTaskQueue.create ~concurrency () in
  let root = Solution.root plan.solution in
  let tasks = Hashtbl.create 100 in

  let isBuilt task =
    let installPath = Task.installPath task in
    let installPath = Scope.SandboxPath.toPath cfg.Config.buildCfg installPath in
    Fs.exists installPath
  in

  let run ~quiet task () =
    if not quiet
    then Logs_lwt.app (fun m -> m "building %a" PackageId.pp task.Task.pkgId)
    else Lwt.return ();%lwt
    let logPath = Task.logPath task in
    let%bind () = buildTask ~cfg ~logPath task in
    if not quiet
    then Logs_lwt.app (fun m -> m "building %a: done" PackageId.pp task.Task.pkgId)
    else Lwt.return ();%lwt
    return ()
  in

  let runIfNeeded pkg =
    let run task () =
      let%bind isBuilt = isBuilt task in
      match task.Task.sourceType with
      | SourceType.Transient ->
        LwtTaskQueue.submit queue (run ~quiet:isBuilt task)
      | SourceType.Immutable ->
        if isBuilt
        then return ()
        else LwtTaskQueue.submit queue (run ~quiet:false task)
    in
    let id = Solution.Package.id pkg in
    match Hashtbl.find_opt tasks id with
    | Some running -> running
    | None ->
      begin match PackageId.Map.find id plan.tasks with
      | Some task ->
        let running =
          RunAsync.contextf
            (run task ())
            "building %a" PackageId.pp id
        in
        Hashtbl.replace tasks id running;
        running
      | None -> RunAsync.return ()
      | exception Not_found -> RunAsync.return ()
      end
  in

  let rec process pkg =
    let id = Solution.Package.id pkg in
    match PackageId.Map.find id plan.tasks with
    | Some _ ->
      let%bind () = processDependencies pkg in
      runIfNeeded pkg
    | None -> RunAsync.return ()
    | exception Not_found -> RunAsync.return ()
  and processDependencies pkg =
    let dependencies =
      let traverse =
        if PackageId.compare (Solution.Package.id root) (Solution.Package.id pkg) = 0
        then Solution.traverseWithDevDependencies
        else Solution.traverse
      in
      Solution.dependencies ~traverse pkg plan.solution
    in
    RunAsync.List.mapAndWait ~f:process dependencies
  in

  match Solution.get id plan.solution with
  | None -> RunAsync.errorf "no such package %a" PackageId.pp id
  | Some pkg -> processDependencies pkg

let exposeUserEnv scope =
  scope
  |> Scope.exposeUserEnvWith Scope.SandboxEnvironment.Bindings.suffixValue "PATH"
  |> Scope.exposeUserEnvWith Scope.SandboxEnvironment.Bindings.suffixValue "MAN_PATH"
  |> Scope.exposeUserEnvWith Scope.SandboxEnvironment.Bindings.value "SHELL"

let exposeDevDependenciesEnv plan task scope =
  let pkg = Solution.getExn task.Task.pkgId plan.solution in
  let f id scope =
    match PackageId.Map.find_opt id plan.tasks with
    | Some (Some task) -> Scope.add ~direct:true ~dep:task.Task.exportedScope scope
    | Some None
    | None -> scope
  in
  PackageId.Set.fold f pkg.Package.devDependencies scope

let buildEnv _sandbox _plan task =
  Scope.env ~includeBuildEnv:true task.Task.buildScope

let commandEnv sandbox plan task =
  let open Run.Syntax in
  let%bind env =
    task.Task.buildScope
    |> exposeUserEnv
    |> exposeDevDependenciesEnv plan task
    |> Scope.env ~includeBuildEnv:true
  in
  let npmBin = Path.show (EsyInstall.SandboxSpec.binPath sandbox) in
  return (
    Scope.SandboxEnvironment.Bindings.prefixValue
      "PATH"
      (Scope.SandboxValue.v npmBin)
    ::env
  )

let execEnv _sandbox plan task =
  task.Task.buildScope
  |> exposeUserEnv
  |> exposeDevDependenciesEnv plan task
  |> Scope.add ~direct:true ~dep:task.Task.exportedScope
  |> Scope.env ~includeBuildEnv:false

let rewritePrefix ~cfg ~origPrefix ~destPrefix rootPath =
  Fastreplacestring.rewritePrefix
    ~fastreplacestringCmd:cfg.Config.fastreplacestringCmd
    ~origPrefix
    ~destPrefix
    rootPath

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
  let%bind () = rewritePrefix ~cfg ~origPrefix ~destPrefix stagePath in
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
      let%bind () = rewritePrefix ~cfg ~origPrefix ~destPrefix:cfg.buildCfg.storePath buildPath in
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
