open Std

(**
 * Build task.
 *
 * TODO: Reconcile with EsyLib.BuildTask, right now we just reuse types & code
 * from there but it probably should live here instead. Fix that after we decide
 * on better package boundaries.
*)

module StringMap = Map.Make(String)
module StringSet = Set.Make(String)
module ConfigPath = Config.ConfigPath

module CommandList = struct
  type t =
    string list list
    [@@deriving (show, eq, ord)]

  let render ~env ~scope (commands : Package.CommandList.t) =
    let open Run.Syntax in
    let env = Environment.Closed.value env in
    let envScope name =
      Environment.Value.find name env
    in
    match commands with
    | None -> Ok []
    | Some commands ->
      let renderCommand =
        let render v =
          let%bind v = CommandExpr.render ~scope v in
          ShellParamExpansion.render ~scope:envScope v
        in
        function
        | Package.CommandList.Command.Parsed args ->
          Result.listMap ~f:render args
        | Package.CommandList.Command.Unparsed string ->
          let%bind string = render string in
          let%bind args = ShellSplit.split string in
          return args
      in
      match Result.listMap ~f:renderCommand commands with
      | Ok commands -> Ok commands
      | Error err -> Error err

end

type t = {
  id : string;
  pkg : Package.t;

  buildCommands : CommandList.t;
  installCommands : CommandList.t;

  env : Environment.Closed.t;
  globalEnv : Environment.binding list;
  localEnv : Environment.binding list;
  paths : paths;

  toolchains : Toolchain.t list;
  dependencies : dependency list;
}
[@@deriving (show, eq, ord)]

and paths = {
  rootPath : ConfigPath.t;
  sourcePath : ConfigPath.t;
  buildPath : ConfigPath.t;
  buildInfoPath : ConfigPath.t;
  stagePath : ConfigPath.t;
  installPath : ConfigPath.t;
  logPath : ConfigPath.t;
}
[@@deriving show]

and dependency =
  | Dependency of t
  | DevDependency of t
  | BuildTimeDependency of t
[@@deriving (show, eq, ord)]

type task = t
type task_dependency = dependency

module DependencySet = Set.Make(struct
  type t = dependency
  let compare = compare_dependency
end)

let taskOf (dep : dependency) =
  match dep with
  | Dependency task -> task
  | DevDependency task -> task
  | BuildTimeDependency task -> task

let safePackageName =
  let replaceAt = Str.regexp "@" in
  let replaceUnderscore = Str.regexp "_+" in
  let replaceSlash = Str.regexp "\\/" in
  let replaceDot = Str.regexp "\\." in
  let replaceDash = Str.regexp "\\-" in
  let make (name : string) =
  name
  |> String.lowercase_ascii
  |> Str.global_replace replaceAt ""
  |> Str.global_replace replaceUnderscore "__"
  |> Str.global_replace replaceSlash "__slash__"
  |> Str.global_replace replaceDot "__dot__"
  |> Str.global_replace replaceDash "_"
  in make

let buildId
  (rootPkg : Package.t)
  (pkg : Package.t)
  (dependencies : dependency list) =
  let digest acc update = Digest.string (acc ^ "--" ^ update) in
  let id =
    ListLabels.fold_left ~f:digest ~init:"" [
      pkg.name;
      pkg.version;
      Package.CommandList.show pkg.buildCommands;
      Package.CommandList.show pkg.installCommands;
      Package.BuildType.show pkg.buildType;
      Package.SandboxEnv.show rootPkg.sandboxEnv;
      (match pkg.resolution with
       | Some resolved -> resolved
       | None -> "")
    ]
  in
  let updateWithDepId id = function
    | Dependency pkg -> digest id pkg.id
    | BuildTimeDependency pkg -> digest id pkg.id
    | DevDependency _ -> id
  in
  let id = ListLabels.fold_left ~f:updateWithDepId ~init:id dependencies in
  let hash = Digest.to_hex id in
  let hash = String.sub hash 0 8 in
  (safePackageName pkg.name ^ "-" ^ pkg.version ^ "-" ^ hash)

let isBuilt ~cfg task =
  Fs.exists ConfigPath.(task.paths.installPath / "lib" |> toPath(cfg))

let getenv name =
  try Some (Sys.getenv name)
  with Not_found -> None

let addTaskBindings
  ?(useStageDirectory=false)
  ~(scopeName : [`Self | `PackageName])
  (pkg : Package.t)
  (paths : paths)
  scope
  =
  let installPath =
    if useStageDirectory
    then paths.stagePath
    else paths.installPath
  in
  let namespace = match scopeName with
  | `Self -> "self"
  | `PackageName -> pkg.name
  in
  let add key value scope =
    StringMap.add (namespace ^ "." ^ key) value scope
  in
  scope
  |> add "name" pkg.name
  |> add "version" pkg.version
  |> add "root" (ConfigPath.toString paths.rootPath)
  |> add "original_root" (ConfigPath.toString pkg.sourcePath)
  |> add "target_dir" (ConfigPath.toString paths.buildPath)
  |> add "install" (ConfigPath.toString installPath)
  |> add "bin" ConfigPath.(installPath / "bin" |> toString)
  |> add "sbin" ConfigPath.(installPath / "sbin" |> toString)
  |> add "lib" ConfigPath.(installPath / "lib" |> toString)
  |> add "man" ConfigPath.(installPath / "man" |> toString)
  |> add "doc" ConfigPath.(installPath / "doc" |> toString)
  |> add "stublibs" ConfigPath.(installPath / "stublibs" |> toString)
  |> add "toplevel" ConfigPath.(installPath / "toplevel" |> toString)
  |> add "share" ConfigPath.(installPath / "share" |> toString)
  |> add "etc" ConfigPath.(installPath / "etc" |> toString)

let addTaskEnvBindings
  (pkg : Package.t)
  (paths : paths)
  (bindings : Environment.binding list) =
  let open Environment in {
    name = "cur__name";
    value = Value pkg.name;
    origin = Some pkg;
  }::{
    name = "cur__version";
    value = Value pkg.version;
    origin = Some pkg;
  }::{
    name = "cur__root";
    value = Value (ConfigPath.toString paths.rootPath);
    origin = Some pkg;
  }::{
    name = "cur__original_root";
    value = Value (ConfigPath.toString pkg.sourcePath);
    origin = Some pkg;
  }::{
    name = "cur__target_dir";
    value = Value (ConfigPath.toString paths.buildPath);
    origin = Some pkg;
  }::{
    name = "cur__install";
    value = Value (ConfigPath.toString paths.stagePath);
    origin = Some pkg;
  }::{
    name = "cur__bin";
    value = Value ConfigPath.(paths.stagePath / "bin" |> toString);
    origin = Some pkg;
  }::{
    name = "cur__sbin";
    value = Value ConfigPath.(paths.stagePath / "sbin" |> toString);
    origin = Some pkg;
  }::{
    name = "cur__lib";
    value = Value ConfigPath.(paths.stagePath / "lib" |> toString);
    origin = Some pkg;
  }::{
    name = "cur__man";
    value = Value ConfigPath.(paths.stagePath / "man" |> toString);
    origin = Some pkg;
  }::{
    name = "cur__doc";
    value = Value ConfigPath.(paths.stagePath / "doc" |> toString);
    origin = Some pkg;
  }::{
    name = "cur__stublibs";
    value = Value ConfigPath.(paths.stagePath / "stublibs" |> toString);
    origin = Some pkg;
  }::{
    name = "cur__toplevel";
    value = Value ConfigPath.(paths.stagePath / "toplevel" |> toString);
    origin = Some pkg;
  }::{
    name = "cur__share";
    value = Value ConfigPath.(paths.stagePath / "share" |> toString);
    origin = Some pkg;
  }::{
    name = "cur__etc";
    value = Value ConfigPath.(paths.stagePath / "etc" |> toString);
    origin = Some pkg;
  }::bindings

let ofPackage
    ?(includeRootDevDependenciesInEnv=false)
    ?(overrideShell=true)
    ?finalPath
    ?finalManPath
    (rootPkg : Package.t)
  =

  let cache = Memoize.create ~size:200 in

  let term = Option.orDefault "" (getenv "TERM") in

  let open Run.Syntax in

  let rec collectDependency
    ?(includeBuildTimeDependencies=true)
    (seen, dependencies)
    dep
    =
    match dep with
    | Package.Dependency depPkg
    | Package.PeerDependency depPkg
    | Package.OptDependency depPkg ->
      if Package.DependencySet.mem dep seen
      then return (seen, dependencies)
      else
        let%bind task = taskOfPackageCached ~includeSandboxEnv:true depPkg in
        let dependencies = (Dependency task)::dependencies in
        let seen = Package.DependencySet.add dep seen in
        return (seen, dependencies)
    | Package.BuildTimeDependency depPkg ->
      if Package.DependencySet.mem dep seen
      then return (seen, dependencies)
      else
        if includeBuildTimeDependencies
        then
          let%bind task = taskOfPackageCached ~includeSandboxEnv:false depPkg in
          let dependencies = (BuildTimeDependency task)::dependencies in
          let seen = Package.DependencySet.add dep seen in
          return (seen, dependencies)
        else
          return (seen, dependencies)
    | Package.DevDependency depPkg ->
      if Package.DependencySet.mem dep seen
      then return (seen, dependencies)
      else
        let%bind task = taskOfPackageCached ~includeSandboxEnv:false depPkg in
        let dependencies = (DevDependency task)::dependencies in
        let seen = Package.DependencySet.add dep seen in
        return (seen, dependencies)
    | Package.InvalidDependency { pkgName; _ } ->
      let msg = Printf.sprintf "missing dependency %s" pkgName in
      Run.error msg

  and directDependenciesOf (pkg : Package.t) =
    let seen = Package.DependencySet.empty in
    let%bind _, dependencies =
      Result.listFoldLeft ~f:collectDependency ~init:(seen, []) pkg.dependencies
    in return (List.rev dependencies)

  and allDependenciesOf (pkg : Package.t) =
    let rec aux ?(includeBuildTimeDependencies=true) _pkg acc dep =
      match Package.packageOf dep with
      | None -> return acc
      | Some depPkg ->
        let%bind acc = Result.listFoldLeft
          ~f:(aux ~includeBuildTimeDependencies:false depPkg)
          ~init:acc
          depPkg.dependencies
        in
        collectDependency ~includeBuildTimeDependencies acc dep
    in
    let seen = Package.DependencySet.empty in
    let%bind _, dependencies =
      Result.listFoldLeft
        ~f:(aux ~includeBuildTimeDependencies:true pkg)
        ~init:(seen, [])
        pkg.dependencies
    in return (List.rev dependencies)

  and uniqueTasksOfDependencies dependencies =
    let f (seen, dependencies) dep =
      let task = taskOf dep in
      if StringSet.mem task.id seen
      then (seen, dependencies)
      else
        let seen = StringSet.add task.id seen in
        let dependencies = task::dependencies in
        (seen, dependencies)
    in
    let _, dependencies =
      ListLabels.fold_left ~f ~init:(StringSet.empty, []) dependencies
    in
    List.rev dependencies

  and taskOfPackage ~(includeSandboxEnv: bool) (pkg : Package.t) =

    let isRoot = pkg.id = rootPkg.id in

    let shouldIncludeDependencyInEnv = function
      | Dependency _ -> true
      | DevDependency _ -> isRoot && includeRootDevDependenciesInEnv
      | BuildTimeDependency _ -> true
    in

    let%bind allDependencies = allDependenciesOf pkg in
    let%bind dependencies = directDependenciesOf pkg in

    let allDependenciesTasks =
      allDependencies
      |> List.filter shouldIncludeDependencyInEnv
      |> uniqueTasksOfDependencies
    in
    let dependenciesTasks =
      dependencies
      |> List.filter shouldIncludeDependencyInEnv
      |> uniqueTasksOfDependencies
    in

    let id = buildId rootPkg pkg dependencies in

    let paths =
      let storePath = match pkg.sourceType with
        | Package.SourceType.Immutable -> ConfigPath.store
        | Package.SourceType.Development
        | Package.SourceType.Root -> ConfigPath.localStore
      in
      let buildPath =
        ConfigPath.(storePath / Config.storeBuildTree / id)
      in
      let buildInfoPath =
        let name = id ^ ".info" in
        ConfigPath.(storePath / Config.storeBuildTree / name)
      in
      let stagePath =
        ConfigPath.(storePath / Config.storeStageTree / id)
      in
      let installPath =
        ConfigPath.(storePath / Config.storeInstallTree / id)
      in
      let logPath =
        let basename = id ^ ".log" in
        ConfigPath.(storePath / Config.storeBuildTree / basename)
      in
      let rootPath =
        match pkg.buildType, pkg.sourceType with
        | InSource, _
        | JBuilderLike, Immutable -> buildPath
        | JBuilderLike, Development
        | JBuilderLike, Root
        | OutOfSource, _ -> pkg.sourcePath
      in {
        rootPath;
        buildPath;
        buildInfoPath;
        stagePath;
        installPath;
        logPath;
        sourcePath = pkg.sourcePath;
      }
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
    let scopeForExportEnv, scopeForCommands =
      let bindings = StringMap.empty in
      let bindings =
        let f bindings task =
          addTaskBindings ~scopeName:`PackageName task.pkg task.paths bindings
        in
        dependenciesTasks
        |> ListLabels.fold_left ~f ~init:bindings
      in
      let bindingsForExportedEnv =
        bindings
        |> addTaskBindings
            ~scopeName:`Self
            pkg
            paths
        |> addTaskBindings
            ~scopeName:`PackageName
            pkg
            paths
      in
      let bindingsForCommands =
        bindings
        |> addTaskBindings
            ~useStageDirectory:true
            ~scopeName:`Self
            pkg
            paths
        |> addTaskBindings
            ~useStageDirectory:true
            ~scopeName:`PackageName
            pkg
            paths
      in
      let lookup bindings name =
        let name = String.concat "." name in
        try Some (StringMap.find name bindings)
        with Not_found -> None
      in
      lookup bindingsForExportedEnv, lookup bindingsForCommands
    in

    let%bind globalEnv, localEnv =
      let f acc Package.ExportedEnv.{name; scope = envScope; value; exclusive = _} =
        let injectCamlLdLibraryPath, globalEnv, localEnv = acc in
        let context = Printf.sprintf "processing exportedEnv $%s" name in
        Run.withContext context (
          let%bind value = CommandExpr.render ~scope:scopeForExportEnv value in
          match envScope with
          | Package.ExportedEnv.Global ->
            let injectCamlLdLibraryPath = name <> "CAML_LD_LIBRARY_PATH" || injectCamlLdLibraryPath in
            let globalEnv = Environment.{origin = Some pkg; name; value = Value value}::globalEnv in
            Ok (injectCamlLdLibraryPath, globalEnv, localEnv)
          | Package.ExportedEnv.Local ->
            let localEnv = Environment.{origin = Some pkg; name; value = Value value}::localEnv in
            Ok (injectCamlLdLibraryPath, globalEnv, localEnv)
        )
      in
      let%bind injectCamlLdLibraryPath, globalEnv, localEnv =
        Run.foldLeft ~f ~init:(false, [], []) pkg.exportedEnv
      in
      let%bind globalEnv = if injectCamlLdLibraryPath then
        let%bind value = CommandExpr.render
          ~scope:scopeForExportEnv
          "#{self.stublibs : self.lib / 'stublibs' : $CAML_LD_LIBRARY_PATH}"
        in
        Ok (Environment.{
              name = "CAML_LD_LIBRARY_PATH";
              value = Value value;
              origin = Some pkg;
            }::globalEnv)
        else
          Ok globalEnv
      in
      return (globalEnv, localEnv)
    in

    let findTask name = allDependenciesTasks
      |> List.find_opt (fun (dep_task: task) -> dep_task.pkg.name = name)
    in

    (* TODO: Add only ocaml-based package paths *)
    let libPaths tasks =
      let libPathForTask task = ConfigPath.(task.paths.installPath / "lib" |> toString) in
      let sep = Environment.PathLike.sep "OCAMLPATH" in
      tasks
      |> List.map libPathForTask
      |> String.concat sep
    in

    (* Configuring ocamlfind toolchains.
     *
     * TODO: Host and target compilers are temporarily
     * hard-coded, we need a better way to collect toolchains.
     *)
    let toolchains = if Toolchain.isCompiler pkg then [] else begin
      let host = (findTask "ocaml", findTask "@opam/ocamlfind") |> function
      | Some ocaml, Some ocamlfind ->
        let sysroot = ocaml.paths.installPath in
        let toolchain = Toolchain.(Ocamlfind (Native, {
          path = libPaths allDependenciesTasks;
          destdir = ConfigPath.(paths.stagePath / "lib" |> toString);
          stdlib = ConfigPath.(ocamlfind.paths.installPath / "lib" / "ocaml" |> toString);
          ldconf = "ignore";
          commands = ConfigPath.(sysroot / "bin") |> ocamlfindCommands;
        }))
        in
        Some toolchain
      | _ -> None
      in

      let target = findTask "ocaml-ios" |> function
      | Some ios ->
        let sysroot = ConfigPath.(ios.paths.installPath / "ios-sysroot") in
        let toolchain = Toolchain.(Ocamlfind (Target "ios", {
          path = ConfigPath.(sysroot / "lib" |> toString);
          destdir = ConfigPath.(paths.stagePath / "lib" |> toString);
          stdlib = ConfigPath.(sysroot / "lib" / "ocaml" |> toString);
          ldconf = "ignore";
          commands = ConfigPath.(sysroot / "bin") |> ocamlfindCommands;
        }))
        in
        Some toolchain
      | None -> None
      in

      List.filterNone [host; target]
    end
    in

    let buildEnv =

      (* All dependencies (transitive included contribute env exported to the
       * global scope (hence global)
      *)
      let globalEnvOfAllDeps =
        let getGlobalEnvForTask task =
          let path = Environment.{
            origin = Some task.pkg;
            name = "PATH";
            value =
              let value = ConfigPath.(task.paths.installPath / "bin" |> toString) in
              Value (value ^ ":$PATH")
          }
          and manPath = Environment.{
            origin = Some task.pkg;
            name = "MAN_PATH";
            value =
              let value = ConfigPath.(task.paths.installPath / "bin" |> toString) in
              Value (value ^ ":$MAN_PATH")
          } in
          path::manPath::task.globalEnv
        in
        allDependenciesTasks
        |> List.map getGlobalEnvForTask
        |> List.concat
        |> List.rev
      in

      (* Direct dependencies contribute only env exported to the local scope
      *)
      let localEnvOfDeps =
        dependenciesTasks
        |> List.map (fun task -> task.localEnv)
        |> List.concat
        |> List.rev
      in

      let initEnv = Environment.[
          {
            name = "TERM";
            value = Value term;
            origin = None;
          };
          {
            name = "PATH";
            value = Value "";
            origin = None;
          };
          {
            name = "MAN_PATH";
            value = Value "";
            origin = None;
          };
          {
            name = "CAML_LD_LIBRARY_PATH";
            value = Value "";
            origin = None;
          };
        ] in

      let sandboxEnv =
        if includeSandboxEnv then
          rootPkg.sandboxEnv |> Environment.ofSandboxEnv
        else []
      in

      let finalEnv = Environment.(
          let v = [
            {
              name = "PATH";
              value = Value (Std.Option.orDefault
                               "$PATH:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                               finalPath);
              origin = None;
            };
            {
              name = "MAN_PATH";
              value = Value (Std.Option.orDefault
                               "$MAN_PATH"
                               finalManPath);
              origin = None;
            };
          ] in
          let v = if List.length toolchains = 0 then v else
            {
              name = "OCAMLFIND_CONF";
              value = Value (ConfigPath.(paths.buildPath / "_esy" / "findlib.conf" |> toString));
              origin = None;
            } :: v
          in
          if overrideShell then
            let shell = {
              name = "SHELL";
              value = Value "env -i /bin/bash --norc --noprofile";
              origin = None;
            } in shell::v
          else
            v
        ) in

      (finalEnv @ (
        (addTaskEnvBindings
            pkg
            paths
            (localEnv @ globalEnv @ localEnvOfDeps @ globalEnvOfAllDeps @ sandboxEnv @ initEnv)
        ))) |> List.rev
    in

    let%bind env =
      Run.withContext
        "evaluating environment"
        (Environment.Closed.ofBindings buildEnv)
    in

    let%bind buildCommands =
      Run.withContext
        "processing esy.build"
        (CommandList.render ~env ~scope:scopeForCommands pkg.buildCommands)
    in
    let%bind installCommands =
      Run.withContext
        "processing esy.install"
        (CommandList.render ~env ~scope:scopeForCommands pkg.installCommands)
    in

    let task: t = {
      id;
      pkg;
      buildCommands;
      installCommands;

      env;
      globalEnv;
      localEnv;
      paths;

      toolchains;
      dependencies;
    } in

    return task

  and taskOfPackageCached ~(includeSandboxEnv: bool) (pkg : Package.t) =
    let v = cache pkg.id (fun () -> taskOfPackage ~includeSandboxEnv pkg) in
    let context =
      Printf.sprintf
        "processing package: %s@%s"
        pkg.name
        pkg.version
    in
    Run.withContext context v
  in

  taskOfPackageCached ~includeSandboxEnv:true rootPkg

let buildEnv pkg =
  let open Run.Syntax in
  let%bind task = ofPackage pkg in
  Ok (Environment.Closed.bindings task.env)

let commandEnv (pkg : Package.t) =
  let open Run.Syntax in

  let%bind task =
    ofPackage
      ?finalPath:(getenv "PATH" |> Std.Option.map ~f:(fun v -> "$PATH:" ^ v))
      ?finalManPath:(getenv "MAN_PATH"|> Std.Option.map ~f:(fun v -> "$MAN_PATH:" ^ v))
      ~overrideShell:false
      ~includeRootDevDependenciesInEnv:true pkg
  in Ok (Environment.Closed.bindings task.env)

let sandboxEnv (pkg : Package.t) =
  let open Run.Syntax in
  let devDependencies =
    pkg.dependencies
    |> List.filter (function | Package.DevDependency _ -> true | _ -> false)
  in
  let synPkg = {
    Package.
    id = "__installation_env__";
    name = "installation_env";
    version = pkg.version;
    dependencies = (Package.Dependency pkg)::devDependencies;
    buildCommands = None;
    installCommands = None;
    buildType = Package.BuildType.OutOfSource;
    sourceType = Package.SourceType.Root;
    exportedEnv = [];
    sandboxEnv = pkg.sandboxEnv;
    sourcePath = pkg.sourcePath;
    resolution = None;
  } in
  let%bind task = ofPackage
      ?finalPath:(getenv "PATH" |> Std.Option.map ~f:(fun v -> "$PATH:" ^ v))
      ?finalManPath:(getenv "MAN_PATH"|> Std.Option.map ~f:(fun v -> "$MAN_PATH:" ^ v))
      ~overrideShell:false
      ~includeRootDevDependenciesInEnv:true
      synPkg
  in Ok (Environment.Closed.bindings task.env)

module DependencyGraph = DependencyGraph.Make(struct
    type t = task

    let compare = Pervasives.compare

    module Dependency = struct
      type t = task_dependency
      let compare = Pervasives.compare
    end

    let id task =
      task.id

    let traverse task =
      let f dep = match dep with
        | Dependency task
        | BuildTimeDependency task
        | DevDependency task -> (task, dep)
      in
      ListLabels.map ~f task.dependencies
  end)

let toBuildProtocol (task : task) =
  let prefix = ConfigPath.(task.paths.buildPath / "_esy") in
  EsyBuildPackage.BuildTask.ConfigFile.{
    id = task.id;
    name = task.pkg.name;
    version = task.pkg.version;
    sourceType = (match task.pkg.sourceType with
        | Package.SourceType.Immutable -> EsyBuildPackage.BuildTask.SourceType.Immutable
        | Package.SourceType.Development -> EsyBuildPackage.BuildTask.SourceType.Transient
        | Package.SourceType.Root -> EsyBuildPackage.BuildTask.SourceType.Root
      );
    buildType = (match task.pkg.buildType with
        | Package.BuildType.InSource -> EsyBuildPackage.BuildTask.BuildType.InSource
        | Package.BuildType.JBuilderLike -> EsyBuildPackage.BuildTask.BuildType.JbuilderLike
        | Package.BuildType.OutOfSource -> EsyBuildPackage.BuildTask.BuildType.OutOfSource
      );
    build = task.buildCommands;
    install = task.installCommands;
    sourcePath = ConfigPath.toString task.paths.sourcePath;
    env = Environment.Closed.value task.env;
    files = List.map (fun (toolchain: Toolchain.t) -> EsyBuildPackage.BuildTask.File. {
      name =
        Toolchain.findlibFilename ~prefix toolchain;
      content = Toolchain.findlibContent toolchain;
    }) task.toolchains;
  }

let toBuildProtocolString ?(pretty=false) (task : task) =
  let task = toBuildProtocol task in
  let json = EsyBuildPackage.BuildTask.ConfigFile.to_yojson task in
  if pretty
  then Yojson.Safe.pretty_to_string json
  else Yojson.Safe.to_string json
