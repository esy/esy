type t = {
  cfg : Config.t;
  path : Path.t;
  root : Package.t;
  dependencies : Package.Dependencies.t;
  resolutions : Package.Resolutions.t;
  ocamlReq : Req.t option;
  origin: origin;
  name : string option;
}

and origin =
  | Esy of Path.t
  | Opam of Path.t
  | AggregatedOpam of Path.t list

module PackageJsonWithResolutions = struct
  type t = {
    resolutions : (Package.Resolutions.t [@default Package.Resolutions.empty]);
  } [@@deriving of_yojson { strict = false }]
end

let ocamlReqAny =
  let spec = VersionSpec.Npm SemverVersion.Formula.any in
  Req.make ~name:"ocaml" ~spec

let makeOpamSandbox ~cfg projectPath (paths : Path.t list) =
  let open RunAsync.Syntax in

  let%bind opams =

    let readOpam (path : Path.t) =
      let%bind data = Fs.readFile path in
      if String.trim data = ""
      then return None
      else
        let name = Path.(path |> remExt |> basename) in
        let%bind manifest =
          let version = OpamPackage.Version.of_string "dev" in
          OpamManifest.ofPath ~name:(OpamPackage.Name.of_string name) ~version path
        in
        return (Some (name, manifest, path))
    in

    let%bind opams =
      paths
      |> List.map ~f:readOpam
      |> RunAsync.List.joinAll
    in

    return (List.filterNone opams)
  in

  let namesPresent =
    let f names (name, _, _) = StringSet.add ("@opam/" ^ name) names in
    List.fold_left ~f ~init:StringSet.empty opams
  in

  let filterFormulaWithNamesPresent (deps : Package.Dep.t list list) =
    let filterDep (dep : Package.Dep.t) = not (StringSet.mem dep.name namesPresent) in
    let filterDisj deps =
      match List.filter ~f:filterDep deps with
      | [] -> None
      | f -> Some f
    in
    deps
    |> List.map ~f:filterDisj
    |> List.filterNone
  in

  let source = Source.LocalPath {
    path = projectPath;
    manifest = None;
  } in
  let version = Version.Source source in

  match opams with
  | [] ->
    let dependencies = Package.Dependencies.NpmFormula [] in
    return {
      cfg;
      path = projectPath;
      root = {
        name = "empty";
        version;
        originalVersion = None;
        source = Source source, [];
        dependencies;
        devDependencies = dependencies;
        opam = None;
        kind = Esy;
      };
      resolutions = Package.Resolutions.empty;
      dependencies = Package.Dependencies.NpmFormula [];
      ocamlReq = Some ocamlReqAny;
      origin = Opam projectPath;
      name = None;
    }
  | opams ->
    let%bind pkgs =
      let f (name, opam, _) =
        match%bind OpamManifest.toPackage ~name ~version opam with
        | Ok pkg -> return pkg
        | Error err -> error err
      in
      RunAsync.List.joinAll (List.map ~f opams)
    in
    let dependencies, devDependencies =
      let f (dependencies, devDependencies) (pkg : Package.t) =
        match pkg.dependencies, pkg.devDependencies with
        | Package.Dependencies.OpamFormula du, Package.Dependencies.OpamFormula ddu ->
          (filterFormulaWithNamesPresent du) @ dependencies,
          (filterFormulaWithNamesPresent ddu) @ devDependencies
        | _ -> assert false
      in
      List.fold_left ~f ~init:([], []) pkgs
    in
    let origin =
      let f (_, _, paths) = paths in
      let paths = List.map ~f opams in
      match paths with
      | [path] -> Opam path
      | paths -> AggregatedOpam paths
    in
    let root = {
      Package.
      name = "root";
      version;
      originalVersion = None;
      source = Package.Source source, [];
      dependencies = Package.Dependencies.OpamFormula dependencies;
      devDependencies = Package.Dependencies.OpamFormula devDependencies;
      opam = None;
      kind = Package.Esy;
    } in

    let dependencies =
      Package.Dependencies.OpamFormula (dependencies @ devDependencies)
    in

    return {
      cfg;
      path = projectPath;
      root;
      resolutions = Package.Resolutions.empty;
      dependencies;
      ocamlReq = Some ocamlReqAny;
      origin;
      name = None;
    }

let makeEsySandbox ?name ~cfg projectPath path =
  let open RunAsync.Syntax in
  let%bind json = Fs.readJsonFile path in

  let%bind pkgJson = RunAsync.ofRun (
    Json.parseJsonWith PackageJson.of_yojson json
  ) in

  let%bind resolutions = RunAsync.ofRun (
    let open Run.Syntax in
    let%bind data = Json.parseJsonWith PackageJsonWithResolutions.of_yojson json in
    return data.PackageJsonWithResolutions.resolutions
  ) in

  let root =
    let source = Source.LocalPath {path = projectPath; manifest = None;} in
    let version = Version.Source source in
    let name = Path.basename projectPath in
    PackageJson.toPackage ~name ~version ~source:(Package.Source source) pkgJson
  in

  let sandboxDependencies, ocamlReq =
    match root.Package.dependencies with
    | Package.Dependencies.OpamFormula _ ->
      root.dependencies, Some ocamlReqAny
    | Package.Dependencies.NpmFormula reqs ->
      let reqs = Package.NpmDependencies.override reqs pkgJson.devDependencies in
      Package.Dependencies.NpmFormula reqs,
      Package.NpmDependencies.find ~name:"ocaml" reqs
  in

  return {
    cfg;
    path = projectPath;
    root;
    resolutions;
    ocamlReq;
    dependencies = sandboxDependencies;
    origin = Esy path;
    name;
  }

let make ~cfg projectPath (sandbox : Project.sandbox) =
  match sandbox with
  | Project.Esy {path; name} -> makeEsySandbox ?name ~cfg projectPath path
  | Project.Opam { path } -> makeOpamSandbox ~cfg projectPath [path]
  | Project.AggregatedOpam { paths } -> makeOpamSandbox ~cfg projectPath paths

let lockfilePath sandbox =
  let filename =
    match sandbox.name with
    | Some name -> "esy." ^ name ^ ".lock.json"
    | None -> "esy.lock.json"
  in
  RunAsync.return Path.(sandbox.path / filename)

let packagesPath sandbox =
  RunAsync.return (
    match sandbox.name with
    | Some name -> Path.(sandbox.path / "_esy" / name / "node_modules")
    | None -> Path.(sandbox.path / "_esy" / "default" / "node_modules")
  )
