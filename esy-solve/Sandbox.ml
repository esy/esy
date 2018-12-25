open EsyPackageConfig

type t = {
  cfg : Config.t;
  spec : EsyInstall.SandboxSpec.t;
  root : Package.t;
  dependencies : Package.Dependencies.t;
  resolutions : PackageConfig.Resolutions.t;
  ocamlReq : Req.t option;
  resolver : Resolver.t;
}

let makeResolution source = {
  PackageConfig.Resolution.
  name = "root";
  resolution = Version (Version.Source source);
}

let ofResolution cfg spec resolver resolution =
  let open RunAsync.Syntax in
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
        let deps = PackageConfig.NpmFormula.override deps devDeps in
        let ocamlReq = PackageConfig.NpmFormula.find ~name:"ocaml" deps in
        Package.Dependencies.NpmFormula deps, ocamlReq
      | Package.Dependencies.NpmFormula _, _
      | Package.Dependencies.OpamFormula _, _  ->
        failwith "mixing npm and opam dependencies"
    in

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

let anyOpam = VersionSpec.Opam (OpamPackageVersion.Formula.any)

let make ~cfg (spec : EsyInstall.SandboxSpec.t) =
  let open RunAsync.Syntax in
  let path = DistPath.make ~base:spec.path spec.path in
  let makeSource manifest =
    Source.Link {path; manifest = Some manifest;}
  in
  RunAsync.contextf (
    let%bind resolver = Resolver.make ~cfg ~sandbox:spec () in
    match spec.manifest with
    | EsyInstall.SandboxSpec.Manifest manifest ->
      let source = makeSource manifest in
      let resolution = makeResolution source in
      let%bind sandbox = ofResolution cfg spec resolver resolution in
      Resolver.setResolutions sandbox.resolutions sandbox.resolver;
      return sandbox
    | EsyInstall.SandboxSpec.ManifestAggregate manifests ->
      let%bind resolutions, reqs, devDeps =
        let f (resolutions, reqs, devDeps) manifest  =
          let source = makeSource manifest in
          let resolution = makeResolution source in
          match%bind Resolver.package ~resolution resolver with
          | Error msg -> errorf "unable to read %a: %s" ManifestSpec.pp manifest msg
          | Ok pkg ->
            let name =
              match ManifestSpec.inferPackageName manifest with
              | None -> failwith "TODO"
              | Some name -> name
            in
            let resolutions =
              let resolution = PackageConfig.Resolution.Version (Version.Source source) in
              PackageConfig.Resolutions.add name resolution resolutions
            in
            let reqs = (Req.make ~name ~spec:anyOpam)::reqs in
            let devDeps =
              match pkg.Package.devDependencies with
              | Package.Dependencies.OpamFormula deps -> deps @ devDeps
              | Package.Dependencies.NpmFormula _ -> devDeps
            in
            return (resolutions, reqs, devDeps)
        in
        RunAsync.List.foldLeft ~f ~init:(PackageConfig.Resolutions.empty, [], []) manifests
      in
      Resolver.setResolutions resolutions resolver;
      let root = {
        Package.
        name = Path.basename spec.path;
        version = Version.Source (Dist NoSource);
        originalVersion = None;
        originalName = None;
        source = PackageSource.Install {
          source = NoSource, [];
          opam = None;
        };
        overrides = Overrides.empty;
        dependencies = Package.Dependencies.NpmFormula reqs;
        devDependencies = Package.Dependencies.OpamFormula devDeps;
        peerDependencies = PackageConfig.NpmFormula.empty;
        optDependencies = StringSet.empty;
        resolutions;
        kind = Npm;
      } in
      return {
        cfg;
        spec;
        root;
        resolutions = root.resolutions;
        ocamlReq = None;
        dependencies = Package.Dependencies.NpmFormula reqs;
        resolver;
      }
  ) "loading root package metadata"
