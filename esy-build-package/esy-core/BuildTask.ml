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

  env : Environment.Normalized.t;

  sourcePath : ConfigPath.t;
  buildPath : ConfigPath.t;
  stagePath : ConfigPath.t;
  installPath : ConfigPath.t;
  logPath : ConfigPath.t;

  dependencies : t list;
}

type task = t

type foldstate = {
  task : task;
  pkg : Package.t;
  buildEnv : Environment.t;
  globalEnv : Environment.t;
  localEnv : Environment.t;
}

let pkgStorePath (pkg : Package.t) = match pkg.sourceType with
  | Package.SourceType.Immutable -> ConfigPath.storePath
  | Package.SourceType.Development
  | Package.SourceType.Root -> ConfigPath.localStorePath

let pkgBuildPath pkg =
  ConfigPath.(pkgStorePath pkg / Config.PackageBuilderConfig.storeBuildTree / pkg.id)

let pkgStagePath pkg =
  ConfigPath.(pkgStorePath pkg / Config.PackageBuilderConfig.storeStageTree / pkg.id)

let pkgInstallPath pkg =
  ConfigPath.(pkgStorePath pkg / Config.PackageBuilderConfig.storeInstallTree / pkg.id)

let pkgLogPath pkg =
  let basename = pkg.Package.id ^ ".log" in
  ConfigPath.(pkgStorePath pkg / Config.PackageBuilderConfig.storeBuildTree / basename)

let rootPath (pkg : Package.t) =
  match pkg.buildType, pkg.sourceType with
  | InSource, _ -> pkgBuildPath pkg
  | JBuilderLike, Immutable -> pkgBuildPath pkg
  | JBuilderLike, Development -> pkg.sourcePath
  | JBuilderLike, Root -> pkg.sourcePath
  | OutOfSource, _ -> pkg.sourcePath

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

let initEnv = Environment.[
  {
    name = "PATH";
    value = "";
    origin = None;
  };
  {
    name = "CAML_LD_LIBRARY_PATH";
    value = "";
    origin = None;
  };
]

let finalEnv = Environment.[
  {
    name = "SHELL";
    value = "env -i /bin/bash --norc --noprofile";
    origin = None;
  };
  {
    name = "PATH";
    value = "$PATH:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
    origin = None;
  };
]

let addPackageEnvBindings (pkg : Package.t) (env : Environment.t) =
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
  }::env

let renderCommandList env scope (commands : Package.CommandList.t) =
  let open Run.Syntax in
  let envScope name =
    Environment.Normalized.find name env
  in
  match commands with
  | None -> Ok None
  | Some commands ->
    let renderCommand command =
      let renderArg arg =
        let%bind arg = CommandExpr.render ~scope arg in
        ShellParamExpansion.render ~scope:envScope arg
      in
      EsyLib.Result.listMap ~f:renderArg command
    in
    match EsyLib.Result.listMap ~f:renderCommand commands with
    | Ok commands -> Ok (Some commands)
    | Error err -> Error err

let ofPackage ?(cache=StringMap.empty) (pkg : Package.t) =
  let open Run.Syntax in

  let f ~allDependencies ~dependencies (pkg : Package.t) =

    let%bind allDependencies, dependencies =
      let f (id, dep) = let%bind dep = dep in Ok (id, dep) in
      let joinDependencies dependencies = EsyLib.Result.listMap ~f dependencies in
      let%bind dependencies = joinDependencies dependencies in
      let%bind allDependencies = joinDependencies allDependencies in
      Ok (allDependencies, dependencies)
    in

    let scope =
      let bindings = StringMap.empty in
      let bindings = addPackageBindings ~kind:`AsSelf pkg bindings in
      let bindings = addPackageBindings ~kind:`AsDep pkg bindings in
      let bindings = ListLabels.fold_left
        ~f:(fun bindings (_, {pkg;_}) -> addPackageBindings ~kind:`AsDep pkg bindings)
        ~init:bindings
        dependencies
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
        |> List.map (fun (_, {globalEnv; _}) -> globalEnv)
        |> List.concat
        |> List.rev
      in

      (* Direct dependencies contribute only env exported to the local scope
       *)
      let localEnvOfDeps =
        dependencies
        |> List.map (fun (_, {localEnv; _}) -> localEnv)
        |> List.concat
        |> List.rev
      in

      (* Now $PATH, $MAN_PATH and $OCAMLPATH are constructed by appending
       * corresponding paths of all dependencies (transtive included).
       *)
      let path, manpath, ocamlpath =
        let f (_, {task = dep; _}) (path, manpath, ocamlpath) =
          let path = ConfigPath.(dep.installPath / "bin")::path in
          let manpath = ConfigPath.(dep.installPath / "man")::manpath in
          let ocamlpath = ConfigPath.(dep.installPath / "lib")::ocamlpath in
          path, manpath, ocamlpath
        in
        ListLabels.fold_right ~f ~init:([], [], []) allDependencies
      in

      let path = Environment.{
        origin = None;
        name = "PATH";
        value =
          let v = List.map ConfigPath.toString path in
          PathLike.make "PATH" v;
      } in

      let manPath = Environment.{
        origin = None;
        name = "MAN_PATH";
        value =
          let v = List.map ConfigPath.toString manpath in
          PathLike.make "MAN_PATH" v;
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
        (Environment.normalize buildEnv)
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

      dependencies = List.map (fun (_, {task = dep; _}) -> dep) dependencies;
    } in

    return { globalEnv; localEnv; buildEnv; pkg; task; }

  in

  let cache = ref cache in

  let f ~allDependencies ~dependencies (pkg : Package.t) =
    try StringMap.find pkg.id !cache
    with Not_found ->
      let v =
        let v = f ~allDependencies ~dependencies pkg in
        let context =
          Printf.sprintf
            "processing package: %s@%s"
            pkg.name
            pkg.version
        in
        Run.withContext context v
      in
      cache := StringMap.add pkg.id v !cache;
      v

  in

  match Package.DependencyGraph.fold ~f pkg with
  | Ok { task; buildEnv; _ } -> Ok (task, buildEnv, !cache)
  | Error msg -> Error msg

module DependencyGraph = DependencyGraph.Make(struct
  type node = task
  type dependency = task

  let id task =
    task.id

  let traverse task =
    List.map (fun dep -> (dep, dep)) task.dependencies
end)

module ExternalFormat = struct

  module SourceType = struct
    type t = Package.SourceType.t

    let to_yojson (sourceType: t) =
      match sourceType with
      | Package.SourceType.Immutable -> `String "immutable"
      | Package.SourceType.Development -> `String "development"
      | Package.SourceType.Root -> `String "root"
  end

  module BuildType = struct
    type t = Package.BuildType.t

    let to_yojson (buildType: t) =
      match buildType with
      | Package.BuildType.InSource -> `String "in-source"
      | Package.BuildType.OutOfSource -> `String "out-of-source"
      | Package.BuildType.JBuilderLike -> `String "_build"
  end

  type t = {
    id : string;
    name : string;
    version : string;
    sourceType : SourceType.t;
    buildType : BuildType.t;
    build: Package.CommandList.t;
    install: Package.CommandList.t;
    sourcePath: ConfigPath.t;
    env: Environment.Normalized.t;
  }
  [@@deriving to_yojson]

  let ofBuildTask (task : task) = {
    id = task.id;
    name = task.pkg.name;
    version = task.pkg.version;
    sourceType = task.pkg.sourceType;
    buildType = task.pkg.buildType;
    build = task.buildCommands;
    install = task.installCommands;
    sourcePath = task.sourcePath;
    env = task.env;
  }

  let toString ?(pretty=false) (task : t) =
    let json = to_yojson task in
    if pretty
    then Yojson.Safe.pretty_to_string json
    else Yojson.Safe.to_string json

end
