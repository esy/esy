(**
 * Build task.
 *)

type dependencyKind =
  | Dependency
  | DevDependency
  | BuildTimeDependency
  [@@deriving ord]

type t = {
  id : string;
  pkg : Sandbox.Package.t;

  buildScope : Scope.t;
  exportedScope : Scope.t;

  build : Sandbox.Value.t list list;
  install : Sandbox.Value.t list list;

  env : Sandbox.Environment.t;

  sourceType : Manifest.SourceType.t;

  dependencies : dependency list;

  platform : System.Platform.t;
}

and dependency = dependencyKind * t

let pp_dependency fmt (dep : dependency) =
  match dep with
  | Dependency, t -> Fmt.pf fmt "Dependency %s" t.id
  | DevDependency, t -> Fmt.pf fmt "DevDependency %s" t.id
  | BuildTimeDependency, t -> Fmt.pf fmt "BuildTimeDependency %s" t.id

let compare a b =
  String.compare a.id b.id

let compare_dependency (ka, pa) (kb, pb) =
  let c = compare_dependencyKind ka kb in
  if c = 0
  then compare pa pb
  else c

let id t = t.id
let pkg t = t.pkg
let sourceType t = t.sourceType
let storePath t = Scope.storePath t.exportedScope
let sourcePath t = Scope.sourcePath t.exportedScope
let rootPath t = Scope.rootPath t.exportedScope
let buildPath t = Scope.buildPath t.exportedScope
let stagePath t = Scope.stagePath t.exportedScope
let installPath t = Scope.installPath t.exportedScope
let buildInfoPath t = Scope.buildInfoPath t.exportedScope
let logPath t = Scope.logPath t.exportedScope
let dependencies t = t.dependencies
let env t = t.env

let plan t =
  {
    EsyBuildPackage.Plan.
    id = t.id;
    name = t.pkg.name;
    version = t.pkg.version;
    sourceType = t.sourceType;
    buildType = t.pkg.build.buildType;
    build = t.build;
    install = t.install;
    sourcePath = Sandbox.Path.toValue t.pkg.sourcePath;
    env = t.env;
  }

let toOCamlVersion version =
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
    match Sandbox.Environment.find name env with
    | Some v -> Some (Sandbox.Value.toString v)
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

  match commands with
  | None -> Ok []
  | Some commands ->
    begin match Result.List.map ~f:renderCommand commands with
    | Ok commands -> Ok commands
    | Error err -> Error err
    end

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
      [Sandbox.Value.v "substs"; Sandbox.Value.v (Path.toString path)]
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
      let cmd = ["patch"; "--strip"; "1"; "--input"; Path.toString path] in
      List.map ~f:Sandbox.Value.v cmd
    in

    return (
      filtered
      |> List.filter ~f:(fun (_, v) -> v)
      |> List.map ~f:toCommand
    )
  ) "processing patch field"

type task = t
type task_dependency = dependency

let renderExpression ~sandbox ~task expr =
  let open Run.Syntax in
  let%bind expr = Scope.renderCommandExpr task.exportedScope expr in
  let expr = Sandbox.Value.v expr in
  let expr = Sandbox.Value.render sandbox.Sandbox.buildConfig expr in
  return expr

let ofSandbox
    ?(forceImmutable=false)
    ?(platform=System.Platform.host)
    (sandbox : Sandbox.t)
  =

  let cache = Memoize.make ~size:200 () in

  let open Run.Syntax in

  let rec allDependenciesOf (pkg : Sandbox.Package.t) =

    let rec aux ?(direct=true) (map, order) dep =

      let%bind dpkg =
        match dep with
        | Ok (Sandbox.Dependency.Dependency, dpkg)
        | Ok (Sandbox.Dependency.OptDependency, dpkg) -> return (Some (dpkg, Dependency))
        | Ok (Sandbox.Dependency.BuildTimeDependency, dpkg) ->
          if direct
          then return (Some (dpkg, BuildTimeDependency))
          else return None
        | Ok (Sandbox.Dependency.DevDependency, dpkg) ->
          if direct
          then return (Some (dpkg, DevDependency))
          else return None
        | Error (Sandbox.Dependency.MissingDependency {name;}) ->
          Run.errorf "package %s is missing, run 'esy install' to fix that" name
        | Error (Sandbox.Dependency.InvalidDependency {name; message;}) ->
          Run.errorf "invalid package %s: %s" name message
      in

      match dpkg with
      | None -> return (map, order)
      | Some (dpkg, dkind) ->

        let seenDep =
          let open Option.Syntax in
          let%bind direct, task = Sandbox.Package.Map.find_opt dpkg map in
          return (direct, task, dpkg)
        in
        match direct, seenDep with
        | false, Some (false, _, _) -> return (map, order)
        | false, Some (true, _, _) -> return (map, order)
        | true, Some (true, _, _) -> return (map, order)
        | true, Some (false, deptask, pkg) ->
          let map = Sandbox.Package.Map.add pkg (true, deptask) map in
          return (map, order)
        | _, None ->
          let%bind (map, order) = Result.List.foldLeft
            ~f:(aux ~direct:false)
            ~init:(map, order)
            (Sandbox.dependencies dpkg sandbox)
          in
          let%bind dtask = taskOfPackageCached dpkg in
          let map = Sandbox.Package.Map.add dpkg (direct, (dkind, dtask)) map in
          let order = dpkg::order in
          return (map, order)
      in

      let%bind map, order =
        Result.List.foldLeft
          ~f:(aux ~direct:true)
          ~init:(Sandbox.Package.Map.empty, [])
          (Sandbox.dependencies pkg sandbox)
      in

      return (
        let f dpkg =
          let task =
            let open Option.Syntax in
            let%bind direct, task = Sandbox.Package.Map.find_opt dpkg map in
            return (direct, task)
          in
          match task with
          | Some v -> v
          | None ->
            let msg = Format.asprintf "task wasn't found: %a" Sandbox.Package.pp dpkg in
            failwith msg
        in
        List.rev_map ~f order
      )

  and taskOfPackage (pkg : Sandbox.Package.t) =

    let ocamlVersion =
      let f pkg = pkg.Sandbox.Package.name = "ocaml" in
      match Sandbox.findPackage f sandbox with
      | Some pkg -> Some (toOCamlVersion pkg.Sandbox.Package.version)
      | None -> None
    in

    let%bind dependencies = allDependenciesOf pkg in

    let id =

      let hash =

        (* include ids of dependencies *)
        let dependencies =
          let f (direct, dependency) =
            match direct, dependency with
            | true, (Dependency, task) -> Some ("dep-" ^ task.id)
            | true, (BuildTimeDependency, task) -> Some ("buildDep-" ^ task.id)
            | true, (DevDependency, _) -> None
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
          pkg.build
          |> Manifest.Build.to_yojson
          |> Yojson.Safe.to_string
        in

        (* a special tag which is communicated by the installer and specifies
         * the version of distribution of vcs commit sha *)
        let source =
          match pkg.source with
          | Some source -> Manifest.Source.toString source
          | None -> ""
        in

        let sandboxEnv =
          sandbox.env
          |> Manifest.Env.to_yojson
          |> Yojson.Safe.to_string
        in

        String.concat "__" (sandboxEnv::source::self::dependencies)
        |> Digest.string
        |> Digest.to_hex
        |> fun hash -> String.sub hash 0 8
      in

      Printf.sprintf "%s-%s-%s" (Path.safeSeg pkg.name) (Path.safePath pkg.version) hash
    in

    let sourceType =
      match forceImmutable, pkg.build.sourceType with
      | true, _ -> Manifest.SourceType.Immutable
      | false, sourceType -> sourceType
    in

    (*
     * Scopes for #{...} syntax.
     *
     * There are two different scopes used to eval "esy.build/esy.install" and
     * "esy.exportedEnv".
     *
     * The only difference is how #{self.<path>} handled:
     * - For "esy.exportedEnv" it expands to "<store>/i/<id>/<path>"
     * - For "esy.build/esy.install" it expands to "<store>/s/<id>/<path>"
     *
     * This is because "esy.exportedEnv" is used when package is already built
     * while "esy.build/esy.install" commands are used while package is
     * building.
     *)
    let exportedScope, buildScope =

      let sandboxEnv =
        let f {Manifest.Env. name; value} =
          Sandbox.Environment.Bindings.value name (Sandbox.Value.v value)
        in
        List.map ~f sandbox.Sandbox.env
      in

      let exportedScope =
        Scope.make
          ~platform
          ~sandboxEnv
          ~id
          ~sourceType
          ~buildIsInProgress:false
          pkg
      in

      let buildScope =
        Scope.make
          ~platform
          ~sandboxEnv
          ~id
          ~sourceType
          ~buildIsInProgress:true
          pkg
      in

      let _, exportedScope, buildScope =
        let f (seen, exportedScope, buildScope) (direct, dep) =
          match dep with
          | DevDependency, _ -> seen, exportedScope, buildScope
          | Dependency, task
          | BuildTimeDependency, task ->
            if StringSet.mem task.id seen
            then seen, exportedScope, buildScope
            else
              StringSet.add task.id seen,
              Scope.add ~direct ~dep:task.exportedScope exportedScope,
              Scope.add ~direct ~dep:task.exportedScope buildScope
        in
        List.fold_left ~f ~init:(StringSet.empty, exportedScope, buildScope) dependencies
      in

      exportedScope, buildScope
    in

    let%bind buildEnv =
      let%bind bindings = Scope.env ~includeBuildEnv:true buildScope in
      Run.context
        (Run.ofStringError (Sandbox.Environment.Bindings.eval bindings))
        "evaluating environment"
    in

    let opamEnv = Scope.toOpamEnv ~ocamlVersion buildScope in

    let%bind build =
      Run.context
        begin match pkg.build.buildCommands with
        | Manifest.Build.EsyCommands commands ->
          let%bind commands = renderEsyCommands ~env:buildEnv buildScope commands in
          let%bind applySubstsCommands = renderOpamSubstsAsCommands opamEnv pkg.build.substs in
          let%bind applyPatchesCommands = renderOpamPatchesToCommands opamEnv pkg.build.patches in
          return (applySubstsCommands @ applyPatchesCommands @ commands)
        | Manifest.Build.OpamCommands commands ->
          let%bind commands = renderOpamCommands opamEnv commands in
          let%bind applySubstsCommands = renderOpamSubstsAsCommands opamEnv pkg.build.substs in
          let%bind applyPatchesCommands = renderOpamPatchesToCommands opamEnv pkg.build.patches in
          return (applySubstsCommands @ applyPatchesCommands @ commands)
        end
        "processing esy.build"
    in

    let%bind install =
      Run.context
        begin match pkg.build.installCommands with
        | Manifest.Build.EsyCommands commands ->
          renderEsyCommands ~env:buildEnv buildScope commands
        | Manifest.Build.OpamCommands commands ->
          renderOpamCommands opamEnv commands
        end
        "processing esy.install"
    in

    let task: t = {
      id;
      pkg;

      build;
      install;
      env = buildEnv;
      sourceType;

      dependencies = (
        dependencies
        |> List.filter ~f:(fun (direct, _) -> direct)
        |> List.map ~f:(fun (_, dep) -> dep)
      );

      platform = platform;
      exportedScope;
      buildScope;
    } in

    return task

  and taskOfPackageCached (pkg : Sandbox.Package.t) =
    Run.contextf
      (Memoize.compute cache pkg.id (fun () -> taskOfPackage pkg))
      "processing package: %s@%s"
      pkg.name
      pkg.version
  in

  taskOfPackageCached sandbox.root

let exposeUserEnv scope =
  scope
  |> Scope.exposeUserEnvWith Sandbox.Environment.Bindings.suffixValue "PATH"
  |> Scope.exposeUserEnvWith Sandbox.Environment.Bindings.suffixValue "MAN_PATH"
  |> Scope.exposeUserEnvWith Sandbox.Environment.Bindings.value "SHELL"

let exposeDevDependenciesEnv task scope =
  let f scope dep =
    match dep with
    | DevDependency, task -> Scope.add ~direct:true ~dep:task.exportedScope scope
    | _ -> scope
  in
  List.fold_left ~f ~init:scope task.dependencies

let buildEnv task = Scope.env ~includeBuildEnv:true task.buildScope

let commandEnv task =
  task.buildScope
  |> exposeUserEnv
  |> exposeDevDependenciesEnv task
  |> Scope.env ~includeBuildEnv:true

let sandboxEnv task =
  task.exportedScope
  |> exposeUserEnv
  |> exposeDevDependenciesEnv task
  |> Scope.add ~direct:true ~dep:task.exportedScope
  |> Scope.env ~includeBuildEnv:false

module Graph = DependencyGraph.Make(struct
    type t = task
    let compare = compare

    module Dependency = struct
      type t = task_dependency
      let compare = compare_dependency
    end

    let id task =
      task.id

    let traverse task =
      let f dep = match dep with
        | Dependency, task
        | BuildTimeDependency, task
        | DevDependency, task -> (task, dep)
      in
      List.map ~f task.dependencies
  end)

(** Check if task is a root task with the current config. *)
let isRoot ~sandbox task =
  sandbox.Sandbox.root.id = task.pkg.id

let rewritePrefix ~(cfg : Config.t) ~origPrefix ~destPrefix rootPath =
  let open RunAsync.Syntax in
  let rewritePrefixInFile path =
    let cmd = Cmd.(cfg.fastreplacestringCommand % p path % p origPrefix % p destPrefix) in
    ChildProcess.run cmd
  in
  let rewriteTargetInSymlink path =
    let%bind link = Fs.readlink path in
    match Path.remPrefix origPrefix link with
    | Some basePath ->
      let nextTargetPath = Path.(destPrefix // basePath) in
      let%bind () = Fs.unlink path in
      let%bind () = Fs.symlink ~src:nextTargetPath path in
      return ()
    | None -> return ()
  in
  let rewrite (path : Path.t) (stats : Unix.stats) =
    match stats.st_kind with
    | Unix.S_REG ->
      rewritePrefixInFile path
    | Unix.S_LNK ->
      rewriteTargetInSymlink path
    | _ -> return ()
  in
  Fs.traverse ~f:rewrite rootPath

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
    let path = Path.(cfg.storePath / "s" / buildId) in
    let%bind () = Fs.rmPath path in
    let%bind () = Fs.copyPath ~src:buildPath ~dst:path in
    return path
  in
  let%bind () = rewritePrefix ~cfg ~origPrefix ~destPrefix stagePath in
  let%bind () = Fs.createDir (Path.parent outputPath) in
  let%bind () =
    ChildProcess.run Cmd.(
      v "tar"
      % "-C" % p (Path.parent stagePath)
      % "-cz"
      % "-f" % p outputPath
      % buildId
    )
  in
  let%lwt () = Logs_lwt.app (fun m -> m "Exporting %s: done" buildId) in
  let%bind () = Fs.rmPath stagePath in
  return ()

let importBuild (cfg : Config.t) buildPath =
  let open RunAsync.Syntax in
  let buildId, kind =
    if Path.hasExt "tar.gz" buildPath
    then
      (buildPath |> Path.remExt |> Path.remExt |> Path.basename, `Archive)
    else
      (buildPath |> Path.basename, `Dir)
  in
  let%lwt () = Logs_lwt.app (fun m -> m "Import %s" buildId) in
  let outputPath = Path.(cfg.storePath / Store.installTree / buildId) in
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
      let%bind () = rewritePrefix ~cfg ~origPrefix ~destPrefix:cfg.storePath buildPath in
      let%bind () = Fs.rename ~src:buildPath outputPath in
      let%lwt () = Logs_lwt.app (fun m -> m "Import %s: done" buildId) in
      return ()
    in
    match kind with
    | `Dir ->
      let%bind stagePath =
        let path = Path.(cfg.storePath / "s" / buildId) in
        let%bind () = Fs.rmPath path in
        let%bind () = Fs.copyPath ~src:buildPath ~dst:path in
        return path
      in
      importFromDir stagePath
    | `Archive ->
      let stagePath = Path.(cfg.storePath / Store.stageTree / buildId) in
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

let isBuilt ~sandbox task =
  let installPath =
    let path = Scope.installPath task.exportedScope in
    Sandbox.Path.(path / "lib")
    |> Sandbox.Path.toPath sandbox.Sandbox.buildConfig
  in
  Fs.exists installPath
