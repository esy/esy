type t = {
  cfg : Config.t;
  path : Path.t;
  root : Package.t;
  dependencies : Package.Dependencies.t;
  resolutions : Manifest.Resolutions.t;
  ocamlReq : Package.Req.t option;
}

module PackageJsonWithResolutions = struct
  type t = {
    resolutions : (Package.Resolutions.t [@default Package.Resolutions.empty]);
  } [@@deriving of_yojson { strict = false }]
end

let readPackageJsonManifest (path : Path.t) =
  let open RunAsync.Syntax in
  match%bind Manifest.find path with
  | Some filename ->
    let%bind json = Fs.readJsonFile filename in
    let%bind pkgJson = RunAsync.ofRun (Json.parseJsonWith Manifest.PackageJson.of_yojson json) in
    let%bind resolutions = RunAsync.ofRun (Json.parseJsonWith PackageJsonWithResolutions.of_yojson json) in
    let manifest = Manifest.ofPackageJson pkgJson in
    return (Some (manifest, resolutions.PackageJsonWithResolutions.resolutions))
  | None -> return None

let readAggregatedOpamManifest (path : Path.t) =
  let open RunAsync.Syntax in
  let%bind filenames = Fs.listDir path in

  let%bind opams =
    let version = OpamPackage.Version.of_string "dev" in
    filenames
    |> List.map ~f:(fun name -> Path.(path / name))
    |> List.filter ~f:(fun path ->
        Path.has_ext ".opam" path || Path.basename path = "opam")
    |> List.map ~f:(fun path ->
        let name = Path.(path |> rem_ext |> basename) in
        let%bind manifest =
          OpamRegistry.Manifest.ofFile ~name:(OpamPackage.Name.of_string name) ~version path
        in
        return (name, manifest))
    |> RunAsync.List.joinAll
  in

  let namesPresent =
    let f names (name, _) = StringSet.add ("@opam/" ^ name) names in
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

  match opams with
  | [] -> return None
  | opams ->
    let%bind pkgs =
      let version = Package.Version.Source (Package.Source.LocalPath path) in
      let f (name, opam) = OpamRegistry.Manifest.toPackage ~name ~version opam in
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
    return (Some (dependencies, devDependencies))

let ocamlReqAny =
  let spec = Package.VersionSpec.Npm SemverVersion.Formula.any in
  Package.Req.ofSpec ~name:"ocaml" ~spec

let ofDir ~cfg (path : Path.t) =
  let open RunAsync.Syntax in
  match%bind readPackageJsonManifest path with
  | Some (manifest, resolutions) ->

    let reqs =
      Package.NpmDependencies.override manifest.Manifest.dependencies manifest.devDependencies
    in

    let ocamlReq = Package.NpmDependencies.find ~name:"ocaml" reqs in

    let%bind root =
      let version = Package.Version.Source (Package.Source.LocalPath path) in
      Manifest.toPackage ~version manifest
    in

    return {
      cfg;
      path;
      root;
      resolutions;
      ocamlReq;
      dependencies = Package.Dependencies.NpmFormula reqs;
    }
  | None ->
    begin match%bind readAggregatedOpamManifest path with
    | Some (dependencies, devDependencies) ->

      let root = {
        Package.
        name = "root";
        version = Package.Version.Source (Package.Source.LocalPath path);
        source = Package.Source (Package.Source.LocalPath path), [];
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
        path;
        root;
        resolutions = Manifest.Resolutions.empty;
        dependencies;
        ocamlReq = Some ocamlReqAny;
      }
    | None -> error "unable to find either package.json or opam files"
    end
