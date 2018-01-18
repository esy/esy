(**
 * Build task.
 *
 * TODO: Reconcile with EsyLib.BuildTask, right now we just reuse types & code
 * from there but it probably should live here instead. Fix that after we decide
 * on better package boundaries.
 *)

module StringMap = Map.Make(String)

type t = {
  id : string;
  pkg : Package.t;

  buildCommands : Package.CommandList.t;
  installCommands : Package.CommandList.t;

  env : Environment.Normalized.t;

  sourcePath : Path.t;
  buildPath : Path.t;
  stagePath : Path.t;
  installPath : Path.t;

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

let storePath (pkg : Package.t) = match pkg.sourceType with
  | Package.SourceType.Immutable -> Path.v "%store%"
  | Package.SourceType.Development
  | Package.SourceType.Root -> Path.v "%localStore%"

let buildPath pkg =
  Path.(storePath pkg / Config.storeBuildTree / pkg.id)

let stagePath pkg =
  Path.(storePath pkg / Config.storeStageTree / pkg.id)

let installPath pkg =
  Path.(storePath pkg / Config.storeInstallTree / pkg.id)

let rootPath (pkg : Package.t) =
  match pkg.buildType, pkg.sourceType with
  | InSource, _ -> buildPath pkg
  | JBuilderLike, Immutable -> buildPath pkg
  | JBuilderLike, Development -> pkg.sourcePath
  | JBuilderLike, Root -> pkg.sourcePath
  | OutOfSource, _ -> pkg.sourcePath

let addPackageBindings ~(kind : [`AsSelf | `AsDep]) (pkg : Package.t) scope =
  let namespace, installPath = match kind with
  | `AsSelf -> "self", stagePath pkg
  | `AsDep -> pkg.name, installPath pkg
  in
  let add key value scope =
    StringMap.add (namespace ^ "." ^ key) value scope
  in
  let buildPath = buildPath pkg in
  let rootPath = rootPath pkg in
  scope
  |> add "name" pkg.name
  |> add "version" pkg.version
  |> add "root" (Path.to_string rootPath)
  |> add "original_root" (Path.to_string pkg.sourcePath)
  |> add "target_dir" (Path.to_string buildPath)
  |> add "install" (Path.to_string installPath)
  |> add "bin" Path.(installPath / "bin" |> to_string)
  |> add "sbin" Path.(installPath / "sbin" |> to_string)
  |> add "lib" Path.(installPath / "lib" |> to_string)
  |> add "man" Path.(installPath / "man" |> to_string)
  |> add "doc" Path.(installPath / "doc" |> to_string)
  |> add "stublibs" Path.(installPath / "stublibs" |> to_string)
  |> add "toplevel" Path.(installPath / "toplevel" |> to_string)
  |> add "share" Path.(installPath / "share" |> to_string)
  |> add "etc" Path.(installPath / "etc" |> to_string)

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
  let buildPath = buildPath pkg in
  let rootPath = rootPath pkg in
  let stagePath = stagePath pkg in
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
    value = Path.to_string rootPath;
    origin = Some pkg;
  }::{
    name = "cur__original_root";
    value = Path.to_string pkg.sourcePath;
    origin = Some pkg;
  }::{
    name = "cur__target_dir";
    value = Path.to_string buildPath;
    origin = Some pkg;
  }::{
    name = "cur__install";
    value = Path.to_string stagePath;
    origin = Some pkg;
  }::{
    name = "cur__bin";
    value = Path.to_string Path.(stagePath / "bin");
    origin = Some pkg;
  }::{
    name = "cur__sbin";
    value = Path.to_string Path.(stagePath / "sbin");
    origin = Some pkg;
  }::{
    name = "cur__lib";
    value = Path.to_string Path.(stagePath / "lib");
    origin = Some pkg;
  }::{
    name = "cur__man";
    value = Path.to_string Path.(stagePath / "man");
    origin = Some pkg;
  }::{
    name = "cur__doc";
    value = Path.to_string Path.(stagePath / "doc");
    origin = Some pkg;
  }::{
    name = "cur__stublibs";
    value = Path.to_string Path.(stagePath / "stublibs");
    origin = Some pkg;
  }::{
    name = "cur__toplevel";
    value = Path.to_string Path.(stagePath / "toplevel");
    origin = Some pkg;
  }::{
    name = "cur__share";
    value = Path.to_string Path.(stagePath / "share");
    origin = Some pkg;
  }::{
    name = "cur__etc";
    value = Path.to_string Path.(stagePath / "etc");
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

let ofPackage (pkg : Package.t) =
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

    let buildPath = buildPath pkg in
    let stagePath = stagePath pkg in
    let installPath = installPath pkg in

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
          let path = Path.(dep.installPath / "bin")::path in
          let manpath = Path.(dep.installPath / "man")::manpath in
          let ocamlpath = Path.(dep.installPath / "lib")::ocamlpath in
          path, manpath, ocamlpath
        in
        ListLabels.fold_right ~f ~init:([], [], []) allDependencies
      in

      let path = Environment.{
        origin = None;
        name = "PATH";
        value = PathLike.make "PATH" path;
      } in

      let manPath = Environment.{
        origin = None;
        name = "MAN_PATH";
        value = PathLike.make "MAN_PATH" manpath;
      } in

      (* Configure environment for ocamlfind.
       * These vars can be used instead of having findlib.conf emitted.
       *)
      let ocamlpath = Environment.{
        origin = None;
        name = "OCAMLPATH";
        value = PathLike.make "OCAMLPATH" ocamlpath;
      } in

      let ocamlfindDestdir = Environment.{
        origin = None;
        name = "OCAMLFIND_DESTDIR";
        value = Path.to_string Path.(stagePath / "lib");
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

      dependencies = List.map (fun (_, {task = dep; _}) -> dep) dependencies;
    } in

    return { globalEnv; localEnv; buildEnv; pkg; task; }

  in

  let f ~allDependencies ~dependencies pkg =
    let v = f ~allDependencies ~dependencies pkg in
    let context =
      Printf.sprintf "processing package: %s@%s" pkg.name pkg.version
    in
    Run.withContext context v
  in

  match Package.DependencyGraph.fold ~f pkg with
  | Ok { task; buildEnv; _ } -> Ok (task, buildEnv)
  | Error msg -> Error msg

module DependencyGraph = DependencyGraph.Make(struct
  type t = task
  let id task = task.id
  let dependencies task = List.map (fun dep -> Some dep) task.dependencies
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
    sourcePath: Path.t;
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
