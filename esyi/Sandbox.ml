type t = {
  cfg : Config.t;
  spec : SandboxSpec.t;
  root : Package.t;
  dependencies : Package.Dependencies.t;
  resolutions : Package.Resolutions.t;
  ocamlReq : Req.t option;
  resolver : Resolver.t;
}

let ocamlReqAny =
  let spec = VersionSpec.Npm SemverVersion.Formula.any in
  Req.make ~name:"ocaml" ~spec

let ofMultiplOpamFiles ~cfg ~spec _projectPath (paths : Path.t list) =
  let open RunAsync.Syntax in

  let%bind resolver = Resolver.make ~cfg ~root:spec.path () in

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

  let source = Source.Link {
    path = Path.v ".";
    manifest = None;
  } in
  let version = Version.Source source in

  match opams with
  | [] ->
    let dependencies = Package.Dependencies.NpmFormula [] in
    return {
      cfg;
      spec;
      root = {
        name = "empty";
        version;
        originalVersion = None;
        originalName = None;
        source = Package.Link {
          path = Path.v ".";
          manifest = None;
          overrides = Package.Overrides.empty;
        };
        dependencies;
        devDependencies = dependencies;
        optDependencies = StringSet.empty;
        resolutions = Package.Resolutions.empty;
        kind = Esy;
      };
      resolver;
      resolutions = Package.Resolutions.empty;
      dependencies = Package.Dependencies.NpmFormula [];
      ocamlReq = Some ocamlReqAny;
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
    let root = {
      Package.
      name = "root";
      version;
      originalVersion = None;
      originalName = None;
      source = Package.Link {
        path = Path.v ".";
        manifest = None;
        overrides = Package.Overrides.empty;
      };
      dependencies = Package.Dependencies.OpamFormula dependencies;
      devDependencies = Package.Dependencies.OpamFormula devDependencies;
      optDependencies = StringSet.empty;
      resolutions = Package.Resolutions.empty;
      kind = Package.Esy;
    } in

    let dependencies =
      Package.Dependencies.OpamFormula (dependencies @ devDependencies)
    in

    return {
      cfg;
      spec;
      root;
      resolutions = Package.Resolutions.empty;
      resolver;
      dependencies;
      ocamlReq = Some ocamlReqAny;
    }

let ofSource ~cfg ~spec source =
  let open RunAsync.Syntax in

  let%bind resolution =
    let version = Version.Source source in
    return {
      Package.Resolution.
      name = "root";
      resolution = Version version;
    }
  in

  let%bind resolver =
    Resolver.make ~cfg ~root:spec.path ()
  in

  match%bind Resolver.package ~resolution resolver with
  | Ok root ->

    let root =
      let name =
        match root.Package.originalName with
        | Some name -> name
        | None -> SandboxSpec.projectName spec
      in
      {root with name;}
    in

    let dependencies, ocamlReq =
      match root.Package.dependencies, root.devDependencies with
      | Package.Dependencies.OpamFormula deps, Package.Dependencies.OpamFormula devDeps ->
        let deps = Package.Dependencies.OpamFormula (deps @ devDeps) in
        deps, None
      | Package.Dependencies.NpmFormula deps, Package.Dependencies.NpmFormula devDeps  ->
        let deps = Package.NpmFormula.override deps devDeps in
        let ocamlReq = Package.NpmFormula.find ~name:"ocaml" deps in
        Package.Dependencies.NpmFormula deps, ocamlReq
      | Package.Dependencies.NpmFormula _, _
      | Package.Dependencies.OpamFormula _, _  ->
        failwith "mixing npm and opam dependencies"
    in

    Resolver.setResolutions root.resolutions resolver;

    return {
      cfg;
      spec;
      root;
      resolutions = root.resolutions;
      ocamlReq;
      dependencies;
      resolver;
    }
  | Error msg -> errorf "unable to construct sandbox: %s" msg

let make ~cfg (spec : SandboxSpec.t) =
  let open RunAsync.Syntax in
  RunAsync.contextf (
    match spec.manifest with
    | ManifestSpec.One (Esy, fname)
    | ManifestSpec.One (Opam, fname) ->
      let source = "link:" ^ fname in
      begin match Source.parse source with
      | Ok source -> ofSource ~cfg ~spec source
      | Error msg -> RunAsync.errorf "unable to construct sandbox: %s" msg
      end
    | ManifestSpec.ManyOpam ->
      let%bind paths = ManifestSpec.findManifestsAtPath spec.path spec.manifest in
      let paths = List.map ~f:(fun (_, filename) -> Path.(spec.path / filename)) paths in
      ofMultiplOpamFiles ~cfg ~spec spec.path paths
  ) "loading root package metadata"
