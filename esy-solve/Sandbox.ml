open EsyPackageConfig

type t = {
  cfg : Config.t;
  spec : EsyInstall.SandboxSpec.t;
  root : InstallManifest.t;
  resolutions : Resolutions.t;
  resolver : Resolver.t;
}

let makeResolution source = {
  Resolution.
  name = "root";
  resolution = Version (Version.Source source);
}

let ofResolution cfg spec resolver resolution =
  let open RunAsync.Syntax in
  match%bind Resolver.package ~resolution resolver with
  | Ok root ->
    let root =
      let name =
        match root.InstallManifest.originalName with
        | Some name -> name
        | None -> EsyInstall.SandboxSpec.projectName spec
      in
      {root with name;}
    in

    return {
      cfg;
      spec;
      root;
      resolutions = root.resolutions;
      resolver;
    }
  | Error msg -> errorf "unable to construct sandbox: %s" msg

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
      let%bind resolutions, deps, devDeps =
        let f (resolutions, deps, devDeps) manifest  =
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
              let resolution = Resolution.Version (Version.Source source) in
              Resolutions.add name resolution resolutions
            in
            let dep = {InstallManifest.Dep.name; req = Opam OpamPackageVersion.Constraint.ANY;} in
            let deps = [dep]::deps in
            let devDeps =
              match pkg.InstallManifest.devDependencies with
              | InstallManifest.Dependencies.OpamFormula deps -> deps @ devDeps
              | InstallManifest.Dependencies.NpmFormula _ -> devDeps
            in
            return (resolutions, deps, devDeps)
        in
        RunAsync.List.foldLeft ~f ~init:(Resolutions.empty, [], []) manifests
      in
      Resolver.setResolutions resolutions resolver;
      let root = {
        InstallManifest.
        name = Path.basename spec.path;
        version = Version.Source (Dist NoSource);
        originalVersion = None;
        originalName = None;
        source = PackageSource.Install {
          source = NoSource, [];
          opam = None;
        };
        overrides = Overrides.empty;
        dependencies = InstallManifest.Dependencies.OpamFormula deps;
        devDependencies = InstallManifest.Dependencies.OpamFormula devDeps;
        peerDependencies = NpmFormula.empty;
        optDependencies = StringSet.empty;
        resolutions;
        kind = Npm;
      } in
      return {
        cfg;
        spec;
        root;
        resolutions = root.resolutions;
        resolver;
      }
  ) "loading root package metadata"
