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
  paths : paths;

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

and dependency =
  | Dependency of t
  | DevDependency of t
  | BuildTimeDependency of t

type task = t
type task_dependency = dependency

type foldstate = {
  task : task;
  pkg : Package.t;
  globalEnv : Environment.binding list;
  localEnv : Environment.binding list;
}

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

  let term = Option.orDefault "" (getenv "TERM") in

  let open Run.Syntax in

  let f ~allDependencies ~dependencies (pkg : Package.t) =

    let isRoot = pkg.id = rootPkg.id in

    let includeDependency = function
      | Package.Dependency _pkg
      | Package.PeerDependency _pkg
      | Package.BuildTimeDependency _pkg
      | Package.OptDependency _pkg -> true
      | Package.DevDependency _pkg -> isRoot && includeRootDevDependenciesInEnv
      | Package.InvalidDependency _ ->
        (** TODO: need to fail gracefully here *)
        failwith "invalid dependency"
    in

    let%bind allDependencies, dependencies =
      let joinDependencies dependencies =
        let f (id, dep) = let%bind dep = dep in Ok (id, dep) in
        Result.listMap ~f dependencies
      in
      let%bind dependencies = joinDependencies dependencies in
      let%bind allDependencies = joinDependencies allDependencies in
      Ok (allDependencies, dependencies)
    in

    let taskDependencies =
      let f (dep, {task; _}) = match dep with
        | Package.DevDependency _ -> DevDependency task
        | Package.BuildTimeDependency _ -> BuildTimeDependency task
        | Package.Dependency _
        | Package.PeerDependency _
        | Package.OptDependency _
        (* TODO: make sure we ignore InvalidDependency *)
        | Package.InvalidDependency _ -> Dependency task
      in
      ListLabels.map ~f dependencies;
    in

    let id =
      buildId pkg taskDependencies
    in

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
        let f bindings (dep, {pkg; task;_}) =
          if includeDependency dep
          then addTaskBindings ~scopeName:`PackageName pkg task.paths bindings
          else bindings
        in
        ListLabels.fold_left ~f ~init:bindings dependencies
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

    let%bind injectCamlLdLibraryPath, globalEnv, localEnv =
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

    let buildEnv =

      (* All dependencies (transitive included contribute env exported to the
       * global scope (hence global)
      *)
      let globalEnvOfAllDeps =
        allDependencies
        |> List.filter (fun (dep, _) -> includeDependency dep)
        |> List.map (fun (_, {globalEnv; _}) -> globalEnv)
        |> List.concat
        |> List.rev
      in

      (* Direct dependencies contribute only env exported to the local scope
      *)
      let localEnvOfDeps =
        dependencies
        |> List.filter (fun (dep, _) -> includeDependency dep)
        |> List.map (fun (_, {localEnv; _}) -> localEnv)
        |> List.concat
        |> List.rev
      in

      (* Now $PATH, $MAN_PATH and $OCAMLPATH are constructed by appending
       * corresponding paths of all dependencies (transtive included).
      *)
      let path, manpath, ocamlpath =
        let f (path, manpath, ocamlpath) (_, {task = dep; _}) =
          let path = ConfigPath.(dep.paths.installPath / "bin")::path in
          let manpath = ConfigPath.(dep.paths.installPath / "man")::manpath in
          let ocamlpath = ConfigPath.(dep.paths.installPath / "lib")::ocamlpath in
          path, manpath, ocamlpath
        in
        allDependencies
        |> ListLabels.filter ~f:(fun (dep, _) -> includeDependency dep)
        |> ListLabels.fold_left ~f ~init:([], [], [])
      in

      let path = Environment.{
          origin = None;
          name = "PATH";
          value = Value (
              let v = List.map ConfigPath.toString path in
              PathLike.make "PATH" v)
        } in

      let manPath = Environment.{
          origin = None;
          name = "MAN_PATH";
          value = Value (
              let v = List.map ConfigPath.toString manpath in
              PathLike.make "MAN_PATH" v)
        } in

      (* Configure environment for ocamlfind.
       * These vars can be used instead of having findlib.conf emitted.
      *)
      let ocamlpath = Environment.{
          origin = None;
          name = "OCAMLPATH";
          value = Value (
              let v = List.map ConfigPath.toString ocamlpath in
              PathLike.make "OCAMLPATH" v);
        } in

      let ocamlfindDestdir = Environment.{
          origin = None;
          name = "OCAMLFIND_DESTDIR";
          value = Value ConfigPath.(paths.stagePath / "lib" |> toString);
        } in

      let ocamlfindLdconf = Environment.{
          origin = None;
          name = "OCAMLFIND_LDCONF";
          value = Value "ignore";
        } in

      let ocamlfindCommands = Environment.{
          origin = None;
          name = "OCAMLFIND_COMMANDS";
          value = Value "ocamlc=ocamlc.opt ocamldep=ocamldep.opt ocamldoc=ocamldoc.opt ocamllex=ocamllex.opt ocamlopt=ocamlopt.opt";
        } in

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
            }
          ] in
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
          path
          ::manPath
          ::ocamlpath
          ::ocamlfindDestdir
          ::ocamlfindLdconf
          ::ocamlfindCommands
          ::(addTaskEnvBindings pkg paths (localEnv @ globalEnv @ localEnvOfDeps @
                                        globalEnvOfAllDeps @ initEnv)))) |> List.rev
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
      paths;

      dependencies = taskDependencies;
    } in

    return { globalEnv; localEnv; pkg; task; }

  in

  let f ~allDependencies ~dependencies (pkg : Package.t) =
    let v = f ~allDependencies ~dependencies pkg in
    let context =
      Printf.sprintf
        "processing package: %s@%s"
        pkg.name
        pkg.version
    in
    Run.withContext context v

  and traverse (pkg : Package.t) =
    let f acc dep = match dep with
      | Package.Dependency dpkg
      | Package.OptDependency dpkg
      | Package.PeerDependency dpkg
      | Package.BuildTimeDependency dpkg
      | Package.DevDependency dpkg -> (dpkg, dep)::acc
      | Package.InvalidDependency _ -> acc
    in
    pkg.dependencies
    |> ListLabels.fold_left ~f ~init:[]
    |> ListLabels.rev
  in

  match Package.DependencyGraph.foldWithAllDependencies ~traverse ~f rootPkg with
  | Ok { task; _ } -> Ok task
  | Error msg -> Error msg

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
  }

let toBuildProtocolString ?(pretty=false) (task : task) =
  let task = toBuildProtocol task in
  let json = EsyBuildPackage.BuildTask.ConfigFile.to_yojson task in
  if pretty
  then Yojson.Safe.pretty_to_string json
  else Yojson.Safe.to_string json
