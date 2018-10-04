module Solution = EsyInstall.Solution
module PackageId = EsyInstall.PackageId
module Record = EsyInstall.Solution.Record
module Installation = EsyInstall.Installation
module Version = EsyInstall.Version

module Task = struct
  type t = {
    id : string;
    name : string;
    version : Version.t;
    env : Sandbox.Environment.t;
    buildCommands : Sandbox.Value.t list list;
    installCommands : Sandbox.Value.t list list;
    sourceType : Manifest.SourceType.t;
    buildScope : Scope.t;
    exportedScope : Scope.t;
    platform : System.Platform.t;
  }

  let id b = PackageId.make b.name b.version
  let compare a b = PackageId.compare (id a) (id b)
end

type t = Task.t PackageId.Map.t

let renderEsyCommands ~env scope commands =
  let open Run.Syntax in
  let envScope name =
    match Sandbox.Environment.find name env with
    | Some v -> Some (Sandbox.Value.show v)
    | None -> None
  in

  let renderArg v =
    let%bind v = Scope.renderCommandExpr scope v in
    Run.ofStringError (EsyShellExpansion.render ~scope:envScope v)
  in

  let renderCommand =
    function
    | Manifest.Command.Parsed args ->
      let f arg =
        let%bind arg = renderArg arg in
        return (Sandbox.Value.v arg)
      in
      Result.List.map ~f args
    | Manifest.Command.Unparsed line ->
      let%bind line = renderArg line in
      let%bind args = ShellSplit.split line in
      return (List.map ~f:Sandbox.Value.v args)
  in

  match Result.List.map ~f:renderCommand commands with
  | Ok commands -> Ok commands
  | Error err -> Error err

let renderOpamCommands opamEnv commands =
  let open Run.Syntax in
  try
    let commands = OpamFilter.commands opamEnv commands in
    let commands = List.map ~f:(List.map ~f:Sandbox.Value.v) commands in
    return commands
  with
    | Failure msg -> error msg

let renderOpamSubstsAsCommands _opamEnv substs =
  let open Run.Syntax in
  let commands =
    let f path =
      let path = Path.addExt ".in" path in
      [Sandbox.Value.v "substs"; Sandbox.Value.v (Path.show path)]
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
      List.map ~f:Sandbox.Value.v cmd
    in

    return (
      filtered
      |> List.filter ~f:(fun (_, v) -> v)
      |> List.map ~f:toCommand
    )
  ) "processing patch field"

let readManifests (installation : Installation.t) =
  let open RunAsync.Syntax in

  let readManifest (id, loc) =
    let%bind manifest =
      match loc with
      | Installation.Install { path; source = _; } ->
        Manifest.ofDir path
      | Installation.Link { path; manifest } ->
        Manifest.ofDir ?manifest path
    in
    return (id, manifest)
  in

  let%bind items =
    Installation.entries installation
    |> List.map ~f:readManifest
    |> RunAsync.List.joinAll
  in

  let paths, manifests =
    let f (paths, manifests) (id, manifest) =
      match manifest with
      | None ->  paths, manifests
      | Some (manifest, manifestPaths) ->
        let paths = Path.Set.union paths manifestPaths in
        let manifests = PackageId.Map.add id manifest manifests in
        paths, manifests
    in
    List.fold_left ~f ~init:(Path.Set.empty, PackageId.Map.empty) items
  in

  return (paths, manifests)

let buildId sandboxEnv build source dependencies =

  let hash =

    (* include ids of dependencies *)
    let dependencies =
      (* let f (direct, dependency) = *)
      (*   match direct, dependency with *)
      (*   | true, (Dependency, task) -> Some ("dep-" ^ task.id) *)
      (*   | true, (BuildTimeDependency, task) -> Some ("buildDep-" ^ task.id) *)
      (*   | true, (DevDependency, _) -> None *)
      (*   | false, _ -> None *)
      (* in *)
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
      |> Manifest.Build.to_yojson
      |> Yojson.Safe.to_string
    in

    (* a special tag which is communicated by the installer and specifies
      * the version of distribution of vcs commit sha *)
    let source =
      match source with
      | Some source -> Manifest.Source.show source
      | None -> "-"
    in

    let sandboxEnv =
      sandboxEnv
      |> Manifest.Env.to_yojson
      |> Yojson.Safe.to_string
    in

    String.concat "__" (sandboxEnv::source::self::dependencies)
    |> Digest.string
    |> Digest.to_hex
    |> fun hash -> String.sub hash 0 8
  in

  Printf.sprintf "%s-%s-%s"
    (Path.safeSeg build.name)
    (Path.safePath (Version.show build.version))
    hash

let make'
  ~platform
  ~buildConfig
  ~sandboxEnv
  ~solution
  ~installation
  ~manifests
  () =
  let open Run.Syntax in

  let tasks = ref PackageId.Map.empty in

  let rec aux record =
    let id = Record.id record in
    match PackageId.Map.find_opt id !tasks with
    | Some None -> return None
    | Some (Some build) -> return (Some build)
    | None ->
      let manifest = PackageId.Map.find id manifests in
      begin match Manifest.build manifest with
      | None -> return None
      | Some build ->
        let%bind build = aux' id record build in
        return (Some build)
      end

  and aux' id record build =
    let location = Installation.findExn id installation in
    let source, sourcePath, sourceType =
      match location with
      | Installation.Install info ->
        Some info.source, info.path, SourceType.Immutable
      | Installation.Link info ->
        None, info.path, SourceType.Transient
    in
    let%bind dependencies =
      let f (direct, record) =
        let%bind build = aux record in
        return (direct, build)
      in
      Result.List.map ~f (Solution.allDependencies record solution)
    in

    let id = buildId Manifest.Env.empty build source dependencies in

    let exportedScope, buildScope =

      let sandboxEnv =
        let f {Manifest.Env. name; value} =
          Sandbox.Environment.Bindings.value name (Sandbox.Value.v value)
        in
        List.map ~f (StringMap.values sandboxEnv)
      in

      let exportedScope =
        Scope.make
          ~platform
          ~sandboxEnv
          ~id
          ~sourceType
          ~sourcePath:(Sandbox.Path.ofPath buildConfig sourcePath)
          ~buildIsInProgress:false
          build
      in

      let buildScope =
        Scope.make
          ~platform
          ~sandboxEnv
          ~id
          ~sourceType
          ~sourcePath:(Sandbox.Path.ofPath buildConfig sourcePath)
          ~buildIsInProgress:true
          build
      in

      let _, exportedScope, buildScope =
        let f (seen, exportedScope, buildScope) (direct, dep) =
          match dep with
          | None -> (seen, exportedScope, buildScope)
          | Some build ->
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
        (Run.ofStringError (Sandbox.Environment.Bindings.eval bindings))
        "evaluating environment"
    in

    let ocamlVersion = failwith "TODO" in

    let opamEnv = Scope.toOpamEnv ~ocamlVersion buildScope in

    let%bind buildCommands =
      Run.context
        begin match build.buildCommands with
        | Manifest.Build.EsyCommands commands ->
          let%bind commands = renderEsyCommands ~env:buildEnv buildScope commands in
          let%bind applySubstsCommands = renderOpamSubstsAsCommands opamEnv build.substs in
          let%bind applyPatchesCommands = renderOpamPatchesToCommands opamEnv build.patches in
          return (applySubstsCommands @ applyPatchesCommands @ commands)
        | Manifest.Build.OpamCommands commands ->
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
        | Manifest.Build.EsyCommands commands ->
          renderEsyCommands ~env:buildEnv buildScope commands
        | Manifest.Build.OpamCommands commands ->
          renderOpamCommands opamEnv commands
        end
        "processing esy.install"
    in

    let task = {
      Task.
      id;
      name = build.name;
      version = build.version;
      buildCommands;
      installCommands;
      env = buildEnv;
      sourceType;
      platform;
      exportedScope;
      buildScope;
    } in

    tasks := PackageId.Map.add (Record.id record) (Some task) !tasks;

    return task

  in

  aux (Solution.root solution)

let make
  ~platform
  ~buildConfig
  ~sandboxEnv
  ~(solution : Solution.t)
  ~(installation : Installation.t) () =
  let open RunAsync.Syntax in
  let%bind _manifestsPath, manifests = readManifests installation in
  let%bind plan = RunAsync.ofRun (
    make'
      ~platform
      ~buildConfig
      ~sandboxEnv
      ~solution
      ~installation
      ~manifests
      ()
  ) in
  return plan
