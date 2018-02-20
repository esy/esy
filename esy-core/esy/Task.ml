open Std

module ConfigPath = Config.ConfigPath
module StringMap = Map.Make(String)
module StringSet = Set.Make(String)

module CommandList : sig
  type t =
    string list list

  val ofPackageCommandList :
    env:Environment.Closed.t
    -> scope:CommandExpr.scope
    -> Package.CommandList.t
    -> t Run.t

  val show : t -> string
  val pp : Format.formatter -> t -> unit

end = struct
  type t =
    string list list
    [@@deriving show]

  let ofPackageCommandList ~env ~scope (commands : Package.CommandList.t) =
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

  sourcePath : ConfigPath.t;
  buildPath : ConfigPath.t;
  stagePath : ConfigPath.t;
  installPath : ConfigPath.t;
  logPath : ConfigPath.t;

  dependencies : dependency list;

  localEnv : Environment.binding list;
  globalEnv : Environment.binding list;
}

and dependency =
  | Dependency of t
  | DevDependency of t
  | BuildDependency of t

type task = t
type task_dependency = dependency

let computeTaskId
  (pkg : Package.t)
  (dependencies : dependency list) =

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
  in

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
    | Dependency task -> digest id task.id
    | BuildDependency task -> digest id task.id
    | DevDependency _ -> id
  in
  let id = ListLabels.fold_left ~f:updateWithDepId ~init:id dependencies in
  let hash = Digest.to_hex id in
  let hash = String.sub hash 0 8 in
  (safePackageName pkg.name ^ "-" ^ pkg.version ^ "-" ^ hash)

let addPackageBindings
  ?(mapSelfToStagePath=false)
  ~(kind : [`AsSelf | `AsDep])
  (pkg : Package.t)
  scope
  =
  let namespace, installPath = match kind with
  | `AsSelf -> "self", if mapSelfToStagePath
                       then Package.Path.stagePath pkg
                       else Package.Path.installPath pkg
  | `AsDep -> pkg.name, Package.Path.installPath pkg
  in
  let add key value scope =
    StringMap.add (namespace ^ "." ^ key) value scope
  in
  let buildPath = Package.Path.buildPath pkg in
  let rootPath = Package.Path.rootPath pkg in
  scope
  |> add "name" pkg.name
  |> add "version" pkg.version
  |> add "root" (ConfigPath.toString rootPath)
  |> add "original_root" (ConfigPath.toString pkg.sourcePath)
  |> add "target_dir" (ConfigPath.toString buildPath)
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

let addPackageEnvBindings (pkg : Package.t) (bindings : Environment.binding list) =
  let buildPath = Package.Path.buildPath pkg in
  let rootPath = Package.Path.rootPath pkg in
  let stagePath = Package.Path.stagePath pkg in
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
      value = Value (ConfigPath.toString rootPath);
      origin = Some pkg;
    }::{
      name = "cur__original_root";
      value = Value (ConfigPath.toString pkg.sourcePath);
      origin = Some pkg;
    }::{
      name = "cur__target_dir";
      value = Value (ConfigPath.toString buildPath);
      origin = Some pkg;
    }::{
      name = "cur__install";
      value = Value (ConfigPath.toString stagePath);
      origin = Some pkg;
    }::{
      name = "cur__bin";
      value = Value ConfigPath.(stagePath / "bin" |> toString);
      origin = Some pkg;
    }::{
      name = "cur__sbin";
      value = Value ConfigPath.(stagePath / "sbin" |> toString);
      origin = Some pkg;
    }::{
      name = "cur__lib";
      value = Value ConfigPath.(stagePath / "lib" |> toString);
      origin = Some pkg;
    }::{
      name = "cur__man";
      value = Value ConfigPath.(stagePath / "man" |> toString);
      origin = Some pkg;
    }::{
      name = "cur__doc";
      value = Value ConfigPath.(stagePath / "doc" |> toString);
      origin = Some pkg;
    }::{
      name = "cur__stublibs";
      value = Value ConfigPath.(stagePath / "stublibs" |> toString);
      origin = Some pkg;
    }::{
      name = "cur__toplevel";
      value = Value ConfigPath.(stagePath / "toplevel" |> toString);
      origin = Some pkg;
    }::{
      name = "cur__share";
      value = Value ConfigPath.(stagePath / "share" |> toString);
      origin = Some pkg;
    }::{
      name = "cur__etc";
      value = Value ConfigPath.(stagePath / "etc" |> toString);
      origin = Some pkg;
    }::bindings

let ofPackage
  ?(overrideShell=true)
  ?finalPath
  ?finalManPath
  (pkg : Package.t) =

  let term = Option.orDefault "" (Environment.Current.get "TERM") in

  let collectDependency (seen, dependencies) = function
    | Package.Dependency pkg
    | Package.PeerDependency pkg
    | Package.OptDependency pkg ->
      if StringSet.mem pkg.id seen
      then (seen, dependencies)
      else
        let seen = StringSet.add pkg.id seen in
        let dependencies = pkg::dependencies in
        (seen, dependencies)
    | Package.DevDependency _
    | Package.BuildDependency _
    | Package.InvalidDependency _ -> (seen, dependencies)
  in

  let collectDependencies (pkg : Package.t) =
    let _, dependencies =
      ListLabels.fold_left
        ~f:collectDependency
        ~init:(StringSet.empty, [])
        pkg.dependencies
    in
    dependencies
  in

  let collectAllDependencies (pkg : Package.t) =
    let rec collect (seen, dependencies) (pkg : Package.t) =
      let f state dep =
        let state = collectDependency state dep in
        match Package.packageOfDependency dep with
        | None -> state
        | Some pkg -> collect state pkg
      in
      ListLabels.fold_left ~f ~init:(seen, dependencies) pkg.dependencies
    in
    let _, dependencies = collect (StringSet.empty, []) pkg in
    dependencies
  in

  let rec packageToTask (pkg : Package.t) =
    let open Run.Syntax in

    let%bind dependencies =
      pkg
      |> collectDependencies
      |> Result.listMap ~f:packageToTask
    in
    let%bind allDependencies =
      pkg
      |> collectAllDependencies
      |> Result.listMap ~f:packageToTask
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
          addPackageBindings ~kind:`AsDep task.pkg bindings
        in
        ListLabels.fold_left ~f ~init:bindings dependencies
      in
      let bindings = addPackageBindings ~kind:`AsDep pkg bindings in
      let bindingsForExportedEnv = addPackageBindings ~kind:`AsSelf pkg bindings in
      let bindingsForCommands = addPackageBindings ~mapSelfToStagePath:true ~kind:`AsSelf pkg bindings in
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

    let buildPath = Package.Path.buildPath pkg in
    let stagePath = Package.Path.stagePath pkg in
    let installPath = Package.Path.installPath pkg in

    let buildEnv =

      (* All dependencies (transitive included contribute env exported to the
       * global scope (hence global)
      *)
      let globalEnvOfAllDeps =
        let collectFrom dependencies v =
          let f bindings {globalEnv; _} = globalEnv::bindings in
          dependencies
          |> ListLabels.fold_left ~f ~init:v
          |> List.rev
        in
        []
        |> collectFrom allDependencies
        |> List.concat
        |> List.rev
      in

      (* Direct dependencies contribute only env exported to the local scope
      *)
      let localEnvOfDeps =
        let collectFrom dependencies v =
          let f bindings {localEnv; _} = localEnv::bindings in
          dependencies
          |> ListLabels.fold_left ~f ~init:v
          |> List.rev
        in
        []
        |> collectFrom dependencies
        |> List.concat
        |> List.rev
      in

      (* Now $PATH, $MAN_PATH and $OCAMLPATH are constructed by appending
       * corresponding paths of all dependencies (transtive included).
      *)
      let path, manpath, ocamlpath =
        let collectFrom dependencies v =
          let f (path, manpath, ocamlpath) dep =
            let path = ConfigPath.(dep.installPath / "bin")::path in
            let manpath = ConfigPath.(dep.installPath / "man")::manpath in
            let ocamlpath = ConfigPath.(dep.installPath / "lib")::ocamlpath in
            path, manpath, ocamlpath
          in
          ListLabels.fold_left ~f ~init:v dependencies
        in
        ([], [], [])
        |> collectFrom allDependencies
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
          value = Value ConfigPath.(stagePath / "lib" |> toString);
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

      List.rev (
        finalEnv @ (
        path
        ::manPath
        ::ocamlpath
        ::ocamlfindDestdir
        ::ocamlfindLdconf
        ::ocamlfindCommands
        ::(addPackageEnvBindings pkg (localEnv @ globalEnv @ localEnvOfDeps @
                                        globalEnvOfAllDeps @ initEnv))))
    in

    let%bind env =
      Run.withContext
        "evaluating environment"
        (Environment.Closed.ofBindings buildEnv)
    in

    let%bind buildCommands =
      Run.withContext
        "processing esy.build"
        (CommandList.ofPackageCommandList ~env ~scope:scopeForCommands pkg.buildCommands)
    in
    let%bind installCommands =
      Run.withContext
        "processing esy.install"
        (CommandList.ofPackageCommandList ~env ~scope:scopeForCommands pkg.installCommands)
    in

    let dependencies = [] in

    let task: t = {
      id = computeTaskId pkg dependencies;

      pkg;
      buildCommands;
      installCommands;

      env;

      sourcePath = pkg.sourcePath;
      buildPath;
      stagePath;
      installPath;
      logPath = Package.Path.logPath pkg;

      dependencies;

      globalEnv;
      localEnv;
    } in

    return task
  in

  packageToTask pkg

let buildEnv pkg =
  let open Run.Syntax in
  let%bind task = ofPackage pkg in
  Ok (Environment.Closed.bindings task.env)

let commandEnv (pkg : Package.t) =
  let open Run.Syntax in

  let%bind task =
    let path = Environment.Current.get "PATH" in
    let manPath = Environment.Current.get "MAN_PATH" in
    ofPackage
      ?finalPath:(Option.map ~f:(fun v -> "$PATH:" ^ v) path)
      ?finalManPath:(Option.map ~f:(fun v -> "$MAN_PATH:" ^ v) manPath)
      ~overrideShell:false
      pkg
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
  let path = Environment.Current.get "PATH" in
  let manPath = Environment.Current.get "MAN_PATH" in
  let%bind task = ofPackage
    ?finalPath:(Option.map ~f:(fun v -> "$PATH:" ^ v) path)
    ?finalManPath:(Option.map ~f:(fun v -> "$MAN_PATH:" ^ v) manPath)
    ~overrideShell:false
    synPkg
  in Ok (Environment.Closed.bindings task.env)

let isBuilt ~cfg task =
  Fs.exists ConfigPath.(task.installPath / "lib" |> toPath(cfg))

module ConfigFile = struct
  include EsyBuildPackage.BuildTask.ConfigFile

  let ofTask (task : task) =
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
      sourcePath = ConfigPath.toString task.sourcePath;
      env = Environment.Closed.value task.env;
    }
end

module DependencyGraph = DependencyGraph.Make(
  struct
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
        | BuildDependency task
        | DevDependency task -> (task, dep)
      in
      ListLabels.map ~f task.dependencies
  end)
