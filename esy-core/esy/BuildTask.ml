open Std

(**
 * Build task.
 *
 * TODO: Reconcile with EsyLib.BuildTask, right now we just reuse types & code
 * from there but it probably should live here instead. Fix that after we decide
 * on better package boundaries.
 *)

module StringMap = Map.Make(String)
module ConfigPath = Config.ConfigPath

type t = {
  id : string;
  pkg : Package.t;

  buildCommands : Package.CommandList.t;
  installCommands : Package.CommandList.t;

  env : Environment.Closed.t;

  sourcePath : ConfigPath.t;
  buildPath : ConfigPath.t;
  stagePath : ConfigPath.t;
  installPath : ConfigPath.t;
  logPath : ConfigPath.t;

  dependencies : dependency list;
}

and dependency =
  | Dependency of t
  | DevDependency of t

type task = t
type task_dependency = dependency

type foldstate = {
  task : task;
  pkg : Package.t;
  globalEnv : Environment.binding list;
  localEnv : Environment.binding list;
}

let pkgStorePath (pkg : Package.t) = match pkg.sourceType with
  | Package.SourceType.Immutable -> ConfigPath.storePath
  | Package.SourceType.Development
  | Package.SourceType.Root -> ConfigPath.localStorePath

let pkgBuildPath pkg =
  ConfigPath.(pkgStorePath pkg / Config.storeBuildTree / pkg.id)

let pkgBuildInfoPath (pkg : Package.t) =
  let name = pkg.id ^ ".info" in
  ConfigPath.(pkgStorePath pkg / Config.storeBuildTree / name)

let pkgStagePath pkg =
  ConfigPath.(pkgStorePath pkg / Config.storeStageTree / pkg.id)

let pkgInstallPath pkg =
  ConfigPath.(pkgStorePath pkg / Config.storeInstallTree / pkg.id)

let pkgLogPath pkg =
  let basename = pkg.Package.id ^ ".log" in
  ConfigPath.(pkgStorePath pkg / Config.storeBuildTree / basename)

let rootPath (pkg : Package.t) =
  match pkg.buildType, pkg.sourceType with
  | InSource, _ -> pkgBuildPath pkg
  | JBuilderLike, Immutable -> pkgBuildPath pkg
  | JBuilderLike, Development -> pkg.sourcePath
  | JBuilderLike, Root -> pkg.sourcePath
  | OutOfSource, _ -> pkg.sourcePath

let getenv name =
  try Some (Sys.getenv name)
  with Not_found -> None

let addPackageBindings ~(kind : [`AsSelf | `AsDep]) (pkg : Package.t) scope =
  let namespace, installPath = match kind with
  | `AsSelf -> "self", pkgStagePath pkg
  | `AsDep -> pkg.name, pkgInstallPath pkg
  in
  let add key value scope =
    StringMap.add (namespace ^ "." ^ key) value scope
  in
  let buildPath = pkgBuildPath pkg in
  let rootPath = rootPath pkg in
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
  let buildPath = pkgBuildPath pkg in
  let rootPath = rootPath pkg in
  let stagePath = pkgStagePath pkg in
  let open Environment in {
    name = "cur__name";
    value = pkg.name;
    origin = Some pkg;
  }::{
    name = "cur__version";
    value = pkg.version;
    origin = Some pkg;
  }::{
    name = "cur__root";
    value = ConfigPath.toString rootPath;
    origin = Some pkg;
  }::{
    name = "cur__original_root";
    value = ConfigPath.toString pkg.sourcePath;
    origin = Some pkg;
  }::{
    name = "cur__target_dir";
    value = ConfigPath.toString buildPath;
    origin = Some pkg;
  }::{
    name = "cur__install";
    value = ConfigPath.toString stagePath;
    origin = Some pkg;
  }::{
    name = "cur__bin";
    value = ConfigPath.(stagePath / "bin" |> toString);
    origin = Some pkg;
  }::{
    name = "cur__sbin";
    value = ConfigPath.(stagePath / "sbin" |> toString);
    origin = Some pkg;
  }::{
    name = "cur__lib";
    value = ConfigPath.(stagePath / "lib" |> toString);
    origin = Some pkg;
  }::{
    name = "cur__man";
    value = ConfigPath.(stagePath / "man" |> toString);
    origin = Some pkg;
  }::{
    name = "cur__doc";
    value = ConfigPath.(stagePath / "doc" |> toString);
    origin = Some pkg;
  }::{
    name = "cur__stublibs";
    value = ConfigPath.(stagePath / "stublibs" |> toString);
    origin = Some pkg;
  }::{
    name = "cur__toplevel";
    value = ConfigPath.(stagePath / "toplevel" |> toString);
    origin = Some pkg;
  }::{
    name = "cur__share";
    value = ConfigPath.(stagePath / "share" |> toString);
    origin = Some pkg;
  }::{
    name = "cur__etc";
    value = ConfigPath.(stagePath / "etc" |> toString);
    origin = Some pkg;
  }::bindings

let renderCommandList env scope (commands : Package.CommandList.t) =
  let open Run.Syntax in
  let env = Environment.Closed.value env in
  let envScope name =
    Environment.Value.find name env
  in
  match commands with
  | None -> Ok None
  | Some commands ->
    let renderCommand command =
      let renderArg arg =
        let%bind arg = CommandExpr.render ~scope arg in
        ShellParamExpansion.render ~scope:envScope arg
      in
      Result.listMap ~f:renderArg command
    in
    match Result.listMap ~f:renderCommand commands with
    | Ok commands -> Ok (Some commands)
    | Error err -> Error err

let ofPackage
    ?(includeRootDevDependenciesInEnv=false)
    ?(overrideShell=true)
    ?initEnv
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

    let scope =
      let bindings = StringMap.empty in
      let bindings = addPackageBindings ~kind:`AsSelf pkg bindings in
      let bindings = addPackageBindings ~kind:`AsDep pkg bindings in
      let bindings =
        let f bindings (dep, {pkg; _}) =
          if includeDependency dep
          then addPackageBindings ~kind:`AsDep pkg bindings
          else bindings
        in
        ListLabels.fold_left ~f ~init:bindings dependencies
      in
      let lookup name =
        let name = String.concat "." name in
        try Some (StringMap.find name bindings)
        with Not_found -> None
      in lookup
    in

    let%bind injectCamlLdLibraryPath, globalEnv, localEnv =
      let f acc Package.ExportedEnv.{name; scope = envScope; value; exclusive = _} =
        let injectCamlLdLibraryPath, globalEnv, localEnv = acc in
        let context = Printf.sprintf "processing exportedEnv $%s" name in
        Run.withContext context (
          let%bind value = CommandExpr.render ~scope value in
          match envScope with
          | Package.ExportedEnv.Global ->
            let injectCamlLdLibraryPath = name <> "CAML_LD_LIBRARY_PATH" || injectCamlLdLibraryPath in
            let globalEnv = Environment.{origin = Some pkg; name; value}::globalEnv in
            Ok (injectCamlLdLibraryPath, globalEnv, localEnv)
          | Package.ExportedEnv.Local ->
            let localEnv = Environment.{origin = Some pkg; name; value}::localEnv in
            Ok (injectCamlLdLibraryPath, globalEnv, localEnv)
        )
      in
      Run.foldLeft ~f ~init:(false, [], []) pkg.exportedEnv
    in

    let%bind globalEnv = if injectCamlLdLibraryPath then
      let%bind value = CommandExpr.render
        ~scope
        "#{self.stublibs : self.lib / 'stublibs' : $CAML_LD_LIBRARY_PATH}"
      in
      Ok (Environment.{
            name = "CAML_LD_LIBRARY_PATH";
            value;
            origin = Some pkg;
          }::globalEnv)
    else
      Ok globalEnv
    in

    let buildPath = pkgBuildPath pkg in
    let stagePath = pkgStagePath pkg in
    let installPath = pkgInstallPath pkg in

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
          let path = ConfigPath.(dep.installPath / "bin")::path in
          let manpath = ConfigPath.(dep.installPath / "man")::manpath in
          let ocamlpath = ConfigPath.(dep.installPath / "lib")::ocamlpath in
          path, manpath, ocamlpath
        in
        allDependencies
        |> ListLabels.filter ~f:(fun (dep, _) -> includeDependency dep)
        |> ListLabels.fold_left ~f ~init:([], [], [])
      in

      let path = Environment.{
        origin = None;
        name = "PATH";
        value =
          let v = List.map ConfigPath.toString path in
          PathLike.make "PATH" v
      } in

      let manPath = Environment.{
        origin = None;
        name = "MAN_PATH";
        value =
          let v = List.map ConfigPath.toString manpath in
          PathLike.make "MAN_PATH" v
      } in

      (* Configure environment for ocamlfind.
       * These vars can be used instead of having findlib.conf emitted.
       *)
      let ocamlpath = Environment.{
        origin = None;
        name = "OCAMLPATH";
        value =
          let v = List.map ConfigPath.toString ocamlpath in
          PathLike.make "OCAMLPATH" v;
      } in

      let ocamlfindDestdir = Environment.{
        origin = None;
        name = "OCAMLFIND_DESTDIR";
        value = ConfigPath.(stagePath / "lib" |> toString);
      } in

      let ocamlfindLdconf = Environment.{
        origin = None;
        name = "OCAMLFIND_LDCONF";
        value = "ignore";
      } in

      let ocamlfindCommands = Environment.{
        origin = None;
        name = "OCAMLFIND_COMMANDS";
        value = "ocamlc=ocamlc.opt ocamldep=ocamldep.opt ocamldoc=ocamldoc.opt ocamllex=ocamllex.opt ocamlopt=ocamlopt.opt";
      } in

      let initEnv = (Std.Option.orDefault [] initEnv) @ Environment.[
        {
          name = "TERM";
          value = term;
          origin = None;
        };
        {
          name = "PATH";
          value = "";
          origin = None;
        };
        {
          name = "MAN_PATH";
          value = "";
          origin = None;
        };
        {
          name = "CAML_LD_LIBRARY_PATH";
          value = "";
          origin = None;
        };
      ] in

      let finalEnv = Environment.(
        let v = [
          {
            name = "PATH";
            value = Std.Option.orDefault
              "$PATH:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
              finalPath;
            origin = None;
          };
          {
            name = "MAN_PATH";
            value = Std.Option.orDefault
              "$MAN_PATH"
              finalManPath;
            origin = None;
          }
        ] in
        if overrideShell then
          let shell = {
            name = "SHELL";
            value = "env -i /bin/bash --norc --noprofile";
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
      ::(addPackageEnvBindings pkg (localEnv @ globalEnv @ localEnvOfDeps @
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
        (renderCommandList env scope pkg.buildCommands)
    in
    let%bind installCommands =
      Run.withContext
        "processing esy.install"
        (renderCommandList env scope pkg.installCommands)
    in

    let task: t = {
      id = pkg.id;

      pkg;
      buildCommands;
      installCommands;

      env;

      sourcePath = pkg.sourcePath;
      buildPath;
      stagePath;
      installPath;
      logPath = pkgLogPath pkg;

      dependencies =
        let f (dep, {task; _}) = match dep with
        | Package.DevDependency _ -> DevDependency task
        | _ -> Dependency task
        in
        ListLabels.map ~f dependencies;
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
  Ok task.env

let initEnv =
  let parseEnv item =
    let idx = String.index item '=' in
    let name = String.sub item 0 idx in
    let value = String.sub item (idx + 1) (String.length item - idx - 1) in
    Environment.{name; value; origin = None;}
  in
  Unix.environment ()
  |> Array.map parseEnv
  |> Array.to_list

let commandEnv pkg =
  let open Run.Syntax in

  let%bind task =
    ofPackage
      ?initEnv:(Some initEnv)
      ?finalPath:(getenv "PATH" |> Std.Option.map ~f:(fun v -> "$PATH:" ^ v))
      ?finalManPath:(getenv "MAN_PATH"|> Std.Option.map ~f:(fun v -> "$MAN_PATH:" ^ v))
      ~overrideShell:false
      ~includeRootDevDependenciesInEnv:true pkg
  in Ok task.env

let sandboxEnv (pkg : Package.t) =
  let open Run.Syntax in
  let synPkg = {
    Package.
    id = "__installation_env__";
    name = "installation_env";
    version = pkg.version;
    dependencies = [Package.Dependency pkg];
    buildCommands = None;
    installCommands = None;
    buildType = Package.BuildType.OutOfSource;
    sourceType = Package.SourceType.Root;
    exportedEnv = [];
    sourcePath = pkg.sourcePath;
  } in
  let%bind task = ofPackage
    ~overrideShell:false
    ?initEnv:(Some initEnv)
    ?finalPath:(getenv "PATH" |> Std.Option.map ~f:(fun v -> "$PATH:" ^ v))
    ?finalManPath:(getenv "MAN_PATH"|> Std.Option.map ~f:(fun v -> "$MAN_PATH:" ^ v))
    synPkg
  in Ok task.env

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
      | DevDependency task -> (task, dep)
    in
    ListLabels.map ~f task.dependencies
end)

let toBuildProtocol (task : task) =
  let exportCommands commands = match commands with
  | None -> []
  | Some commands -> commands
  in
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
    build = exportCommands task.buildCommands;
    install = exportCommands task.installCommands;
    sourcePath = ConfigPath.toString task.sourcePath;
    env = Environment.Closed.value task.env;
  }

let toBuildProtocolString ?(pretty=false) (task : task) =
  let task = toBuildProtocol task in
  let json = EsyBuildPackage.BuildTask.ConfigFile.to_yojson task in
  if pretty
  then Yojson.Safe.pretty_to_string json
  else Yojson.Safe.to_string json
