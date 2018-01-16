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
  name : string;
  version : string;

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

let renderCommandList scope (commands : Package.CommandList.t) =
  match commands with
  | None -> Ok None
  | Some commands ->
    let renderCommand command =
      let renderArg arg = CommandExpr.render ~scope arg in
      EsyLib.Result.listMap ~f:renderArg command
    in
    match EsyLib.Result.listMap ~f:renderCommand commands with
    | Ok commands -> Ok (Some commands)
    | Error err -> Error err

let renderEnvironment scope (env : Environment.t) =
  let renderEnvironmentBinding (binding : Environment.binding) =
    match CommandExpr.render ~scope binding.value with
    | Ok value -> Ok { binding with value }
    | Error err -> Error err
  in
  EsyLib.Result.listMap ~f:renderEnvironmentBinding env

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

    let globalEnv, localEnv =
      let f (globalEnv, localEnv) Package.ExportedEnv.{name; scope; value; exclusive = _} =
        match scope with
        | Package.ExportedEnv.Global ->
          let globalEnv = Environment.{origin = Some pkg; name; value}::globalEnv in
          globalEnv, localEnv
        | Package.ExportedEnv.Local ->
          let localEnv = Environment.{origin = Some pkg; name; value}::localEnv in
          globalEnv, localEnv
      in
      ListLabels.fold_left ~f ~init:([], []) pkg.exportedEnv
    in

    let buildPath = buildPath pkg in
    let stagePath = stagePath pkg in
    let installPath = installPath pkg in

    let env =

      (* All dependencies (transitive included contribute env exported to the
       * global scope (hence global)
       *)
      let globalEnv =
        allDependencies
        |> List.map (fun (_, {globalEnv; _}) -> globalEnv)
        |> List.concat
      in

      (* Direct dependencies contribute only env exported to the local scope
       *)
      let localEnv =
        dependencies
        |> List.map (fun (_, {localEnv; _}) -> localEnv)
        |> List.concat
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

      path
      ::manPath
      ::ocamlpath
      ::ocamlfindDestdir
      ::ocamlfindLdconf
      ::ocamlfindCommands
      ::(addPackageEnvBindings pkg (localEnv @ globalEnv))
    in

    let scope =
      let bindings = StringMap.empty in
      let bindings = addPackageBindings ~kind:`AsSelf pkg bindings in
      let bindings = ListLabels.fold_left
        ~f:(fun bindings (_, {pkg;_}) -> addPackageBindings ~kind:`AsDep pkg bindings)
        ~init:bindings
        dependencies
      in
      let lookup name =
        let name = String.concat "." name in
        try Some (StringMap.find name bindings)
        with Not_found ->
          print_endline "oops";
          StringMap.iter (fun key _v -> print_endline key) bindings;
          None
      in lookup
    in

    let%bind buildEnv =
      Run.withContext
        "While processing environment"
        (renderEnvironment scope env)
    in

    let%bind buildCommands =
      Run.withContext
        "While processing esy.build"
        (renderCommandList scope pkg.buildCommands)
    in
    let%bind installCommands =
      Run.withContext
        "While processing esy.install"
        (renderCommandList scope pkg.installCommands)
    in

    let%bind env = Environment.normalize buildEnv in

    let task: t = {
      id = pkg.id;
      name = pkg.name;
      version = pkg.version;
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
      Printf.sprintf "While processing package: %s@%s" pkg.name pkg.version
    in
    Run.withContext context v
  in

  match Package.fold ~f pkg with
  | Ok { task; buildEnv; _ } -> Ok (task, buildEnv)
  | Error msg -> Error msg

(**
 * Fold over a task dependency graph.
 *)
let fold ~(f : ('t, 'a) DependencyGraph.folder) (pkg : t) =
  let idOf (pkg : t) = pkg.id in
  let dependenciesOf pkg =
    List.map (fun dep -> Some dep) pkg.dependencies
  in
  DependencyGraph.fold ~idOf ~dependenciesOf ~f pkg
