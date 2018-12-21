type t = {
  cfg : Config.t;
  spec : EsyInstall.SandboxSpec.t;
  root : Package.t;
  dependencies : Package.Dependencies.t;
  resolutions : EsyInstall.PackageConfig.Resolutions.t;
  ocamlReq : EsyInstall.Req.t option;
  resolver : Resolver.t;
}

let ocamlReqAny =
  let spec = EsyInstall.VersionSpec.Npm EsyInstall.SemverVersion.Formula.any in
  EsyInstall.Req.make ~name:"ocaml" ~spec

let ofMultiplOpamFiles ~cfg ~spec _projectPath (paths : Path.t list) =
  let open RunAsync.Syntax in

  let%bind resolver = Resolver.make ~cfg ~sandbox:spec () in

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

  let source = EsyInstall.Source.Link {
    path = EsyInstall.DistPath.v ".";
    manifest = None;
  } in
  let version = EsyInstall.Version.Source source in

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
        source = EsyInstall.PackageSource.Link {
          path = EsyInstall.DistPath.v ".";
          manifest = None;
        };
        overrides = EsyInstall.Overrides.empty;
        dependencies;
        devDependencies = dependencies;
        peerDependencies = EsyInstall.PackageConfig.NpmFormula.empty;
        optDependencies = StringSet.empty;
        resolutions = EsyInstall.PackageConfig.Resolutions.empty;
        kind = Esy;
      };
      resolver;
      resolutions = EsyInstall.PackageConfig.Resolutions.empty;
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
      source = EsyInstall.PackageSource.Link {
        path = EsyInstall.DistPath.v ".";
        manifest = None;
      };
      overrides = EsyInstall.Overrides.empty;
      dependencies = Package.Dependencies.OpamFormula dependencies;
      devDependencies = Package.Dependencies.OpamFormula devDependencies;
      peerDependencies = EsyInstall.PackageConfig.NpmFormula.empty;
      optDependencies = StringSet.empty;
      resolutions = EsyInstall.PackageConfig.Resolutions.empty;
      kind = Package.Esy;
    } in

    let dependencies =
      Package.Dependencies.OpamFormula (dependencies @ devDependencies)
    in

    return {
      cfg;
      spec;
      root;
      resolutions = EsyInstall.PackageConfig.Resolutions.empty;
      resolver;
      dependencies;
      ocamlReq = Some ocamlReqAny;
    }

let ofSource ~cfg ~spec source =
  let open RunAsync.Syntax in

  let%bind resolution =
    let version = EsyInstall.Version.Source source in
    return {
      EsyInstall.PackageConfig.Resolution.
      name = "root";
      resolution = Version version;
    }
  in

  let%bind resolver =
    Resolver.make ~cfg ~sandbox:spec ()
  in

  match%bind Resolver.package ~resolution resolver with
  | Ok root ->

    let root =
      let name =
        match root.Package.originalName with
        | Some name -> name
        | None -> EsyInstall.SandboxSpec.projectName spec
      in
      {root with name;}
    in

    let dependencies, ocamlReq =
      match root.Package.dependencies, root.devDependencies with
      | Package.Dependencies.OpamFormula deps, Package.Dependencies.OpamFormula devDeps ->
        let deps = Package.Dependencies.OpamFormula (deps @ devDeps) in
        deps, None
      | Package.Dependencies.NpmFormula deps, Package.Dependencies.NpmFormula devDeps  ->
        let deps = EsyInstall.PackageConfig.NpmFormula.override deps devDeps in
        let ocamlReq = EsyInstall.PackageConfig.NpmFormula.find ~name:"ocaml" deps in
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

let make ~cfg (spec : EsyInstall.SandboxSpec.t) =
  RunAsync.contextf (
    match spec.manifest with
    | EsyInstall.SandboxSpec.Manifest (Esy, fname)
    | EsyInstall.SandboxSpec.Manifest (Opam, fname) ->
      let source = "link:" ^ fname in
      begin match EsyInstall.Source.parse source with
      | Ok source -> ofSource ~cfg ~spec source
      | Error msg -> RunAsync.errorf "unable to construct sandbox: %s" msg
      end
    | EsyInstall.SandboxSpec.ManifestAggregate _ ->
      let paths = EsyInstall.SandboxSpec.manifestPaths spec in
      ofMultiplOpamFiles ~cfg ~spec spec.path paths
  ) "loading root package metadata"
