(**
 * Build task.
 *
 * TODO: Reconcile with EsyLib.BuildTask, right now we just reuse types & code
 * from there but it probably should live here instead. Fix that after we decide
 * on better package boundaries.
 *)

module Environment = struct

  type t = item list
  and item = { origin : Package.t option; name : string; value : string }

  module PathLike = struct

    let make (name : string) (value : Path.t list) =
      let sep = match System.host, name with
        | System.Cygwin, "OCAMLPATH" -> ";"
        | _ -> ":"
      in
      value |> List.map Path.to_string |> String.concat sep

  end
end

type t = {
  id : string;
  name : string;
  version : string;
  buildCommands : Package.CommandList.t option;
  installCommands : Package.CommandList.t option;

  env : Environment.t;

  sourcePath : Path.t;
  buildPath : Path.t;
  stagePath : Path.t;
  installPath : Path.t;

  dependencies : t list;
}

type task = t

let ofPackage (pkg : Package.t) =

  (* Fold over package dependency graph *)
  let fold =
    let idOf (pkg : Package.t) = pkg.id in
    let dependenciesOf pkg =
      let open Package in
      List.map
        (function | Dependency p | PeerDependency p -> Some p | _ -> None)
        pkg.dependencies
    in
    DependencyGraph.fold ~idOf ~dependenciesOf
  in

  let exportedEnv (pkg : Package.t) =
    let f (globalEnv, localEnv) Package.ExportedEnv.{name; scope; value; exclusive = _} =
      match scope with
      | Package.ExportedEnv.Global ->
          let globalEnv = Environment.{origin = Some pkg; name; value}::globalEnv in
        (globalEnv, localEnv)
      | Package.ExportedEnv.Local ->
          let localEnv = Environment.{origin = Some pkg; name; value}::localEnv in
        (globalEnv, localEnv)
    in
    ListLabels.fold_left ~f ~init:([], []) pkg.exportedEnv
  in

  let f ~allDependencies ~dependencies (pkg : Package.t) =
    print_endline pkg.id;

    let globalEnv, localEnv = exportedEnv pkg in

    let storePath = match pkg.sourceType with
        | Package.Immutable -> Path.v "%store%"
        | Package.Development
        | Package.Root -> Path.v "%localStore%"
    in

    let buildPath = Path.(storePath / Config.storeBuildTree / pkg.id) in
    let stagePath = Path.(storePath / Config.storeStageTree / pkg.id) in
    let installPath = Path.(storePath / Config.storeInstallTree / pkg.id) in

    let rootPath =
      let open Package.EsyManifest in
      match pkg.buildType, pkg.sourceType with
      | InSource, _ -> buildPath
      | JBuilderLike, Immutable -> buildPath
      | JBuilderLike, Development -> pkg.sourcePath
      | JBuilderLike, Root -> pkg.sourcePath
      | OutOfSource, _ -> pkg.sourcePath
    in

    let env =

      let globalEnv =
        allDependencies
        |> List.map (fun (_, (globalEnv, _, _)) -> globalEnv)
        |> List.concat
      in

      let localEnv =
        dependencies
        |> List.map (fun (_, (_, localEnv, _)) -> localEnv)
        |> List.concat
      in

      let path, manpath, ocamlpath =
        let f (_, (_, _, dep)) (path, manpath, ocamlpath) =
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

      let curName = Environment.{
        name = "cur__name";
        value = pkg.name;
        origin = Some pkg;
      } in
      let curVersion = Environment.{
        name = "cur__version";
        value = pkg.version;
        origin = Some pkg;
      } in
      let curRoot = Environment.{
        name = "cur__root";
        value = Path.to_string rootPath;
        origin = Some pkg;
      } in
      let curOriginalRoot = Environment.{
        name = "cur__original_root";
        value = Path.to_string pkg.sourcePath;
        origin = Some pkg;
      } in
      let curDepends = Environment.{
        name = "cur__depends";
        value =
          dependencies
          |> List.map (fun (_, (_, _, (dep: task))) -> dep.name)
          |> String.concat "";
        origin = Some pkg;
      } in
      let curTargetDir = Environment.{
        name = "cur__target_dir";
        value = Path.to_string buildPath;
        origin = Some pkg;
      } in
      let curInstall = Environment.{
        name = "cur__install";
        value = Path.to_string stagePath;
        origin = Some pkg;
      } in
      let curBin = Environment.{
        name = "cur__bin";
        value = Path.to_string Path.(stagePath / "bin");
        origin = Some pkg;
      } in
      let curSbin = Environment.{
        name = "cur__sbin";
        value = Path.to_string Path.(stagePath / "sbin");
        origin = Some pkg;
      } in
      let curLib = Environment.{
        name = "cur__lib";
        value = Path.to_string Path.(stagePath / "lib");
        origin = Some pkg;
      } in
      let curMan = Environment.{
        name = "cur__man";
        value = Path.to_string Path.(stagePath / "man");
        origin = Some pkg;
      } in
      let curDoc = Environment.{
        name = "cur__doc";
        value = Path.to_string Path.(stagePath / "doc");
        origin = Some pkg;
      } in
      let curStublibs = Environment.{
        name = "cur__stublibs";
        value = Path.to_string Path.(stagePath / "stublibs");
        origin = Some pkg;
      } in
      let curToplevel = Environment.{
        name = "cur__toplevel";
        value = Path.to_string Path.(stagePath / "toplevel");
        origin = Some pkg;
      } in
      let curShare = Environment.{
        name = "cur__share";
        value = Path.to_string Path.(stagePath / "share");
        origin = Some pkg;
      } in
      let curEtc = Environment.{
        name = "cur__etc";
        value = Path.to_string Path.(stagePath / "etc");
        origin = Some pkg;
      } in

      path
      ::manPath
      ::ocamlpath
      ::ocamlfindDestdir
      ::ocamlfindLdconf
      ::ocamlfindCommands
      ::curName
      ::curVersion
      ::curDepends
      ::curTargetDir
      ::curRoot
      ::curOriginalRoot
      ::curInstall
      ::curBin
      ::curSbin
      ::curLib
      ::curStublibs
      ::curEtc
      ::curDoc
      ::curMan
      ::curShare
      ::curToplevel
      ::(localEnv @ globalEnv)
    in

    let task: t = {
      id = pkg.id;
      name = pkg.name;
      version = pkg.version;
      buildCommands = Some pkg.buildCommands;
      installCommands = Some pkg.buildCommands;
      env;

      sourcePath = pkg.sourcePath;
      buildPath;
      stagePath;
      installPath;

      dependencies = List.map (fun (_, (_, _, dep)) -> dep) dependencies;
    } in

    (globalEnv, localEnv, task)

  in

  let _, _, task = fold ~f pkg in
  task
