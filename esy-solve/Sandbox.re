open EsyPackageConfig;

type t = {
  cfg: Config.t,
  spec: EsyInstall.SandboxSpec.t,
  root: InstallManifest.t,
  resolutions: Resolutions.t,
  resolver: Resolver.t,
};

let makeResolution = source => {
  Resolution.name: "root",
  resolution: Version(Version.Source(source)),
};

let ofResolution =
    (~gitUsername, ~gitPassword, cfg, spec, resolver, resolution) => {
  open RunAsync.Syntax;
  switch%bind (
    Resolver.package(~gitUsername, ~gitPassword, ~resolution, resolver)
  ) {
  | Ok(root) =>
    let root = {
      let name =
        switch (root.InstallManifest.originalName) {
        | Some(name) => name
        | None => EsyInstall.SandboxSpec.projectName(spec)
        };

      {...root, name};
    };

    return({cfg, spec, root, resolutions: root.resolutions, resolver});
  | Error(msg) => errorf("unable to construct sandbox: %s", msg)
  };
};

let make = (~gitUsername, ~gitPassword, ~cfg, spec: EsyInstall.SandboxSpec.t) => {
  open RunAsync.Syntax;
  let path = DistPath.make(~base=spec.path, spec.path);
  let makeSource = manifest =>
    Source.Link({path, manifest: Some(manifest), kind: LinkDev});

  RunAsync.contextf(
    {
      let* resolver = Resolver.make(~cfg, ~sandbox=spec, ());
      switch (spec.manifest) {
      | EsyInstall.SandboxSpec.Manifest(manifest) =>
        let source = makeSource(manifest);
        let resolution = makeResolution(source);
        let* sandbox =
          ofResolution(
            ~gitUsername,
            ~gitPassword,
            cfg,
            spec,
            resolver,
            resolution,
          );
        Resolver.setResolutions(sandbox.resolutions, sandbox.resolver);
        return(sandbox);
      | EsyInstall.SandboxSpec.ManifestAggregate(manifests) =>
        let* (resolutions, deps, devDeps) = {
          let f = ((resolutions, deps, devDeps), manifest) => {
            let source = makeSource(manifest);
            let resolution = makeResolution(source);
            switch%bind (
              Resolver.package(
                ~gitUsername,
                ~gitPassword,
                ~resolution,
                resolver,
              )
            ) {
            | Error(msg) =>
              errorf("unable to read %a: %s", ManifestSpec.pp, manifest, msg)
            | Ok(pkg) =>
              let name =
                switch (ManifestSpec.inferPackageName(manifest)) {
                | None => failwith("TODO")
                | Some(name) => name
                };

              let resolutions = {
                let resolution = Resolution.Version(Version.Source(source));
                Resolutions.add(name, resolution, resolutions);
              };

              let dep = {
                InstallManifest.Dep.name,
                req: Opam(OpamPackageVersion.Constraint.ANY),
              };
              let deps = [[dep], ...deps];
              let devDeps =
                switch (pkg.InstallManifest.devDependencies) {
                | InstallManifest.Dependencies.OpamFormula(deps) =>
                  deps @ devDeps
                | InstallManifest.Dependencies.NpmFormula(_) => devDeps
                };

              return((resolutions, deps, devDeps));
            };
          };

          RunAsync.List.foldLeft(
            ~f,
            ~init=(Resolutions.empty, [], []),
            manifests,
          );
        };

        Resolver.setResolutions(resolutions, resolver);
        let root = {
          InstallManifest.name: Path.basename(spec.path),
          version: Version.Source(Dist(NoSource)),
          originalVersion: None,
          originalName: None,
          source:
            PackageSource.Install({source: (NoSource, []), opam: None}),
          overrides: Overrides.empty,
          dependencies: InstallManifest.Dependencies.OpamFormula(deps),
          devDependencies: InstallManifest.Dependencies.OpamFormula(devDeps),
          peerDependencies: NpmFormula.empty,
          optDependencies: StringSet.empty,
          resolutions,
          kind: Npm,
          installConfig: InstallConfig.empty,
          extraSources: [],
        };
        return({cfg, spec, root, resolutions: root.resolutions, resolver});
      };
    },
    "loading root package metadata",
  );
};

let digest = (solvespec, sandbox) => {
  open RunAsync.Syntax;

  let ppDependencies = (fmt, deps) => {
    let ppOpamDependencies = (fmt, deps) => {
      let ppDisj = (fmt, disj) =>
        switch (disj) {
        | [] => Fmt.unit("true", fmt, ())
        | [dep] => InstallManifest.Dep.pp(fmt, dep)
        | deps =>
          Fmt.pf(
            fmt,
            "(%a)",
            Fmt.(list(~sep=unit(" || "), InstallManifest.Dep.pp)),
            deps,
          )
        };

      Fmt.pf(
        fmt,
        "@[<h>[@;%a@;]@]",
        Fmt.(list(~sep=unit(" && "), ppDisj)),
        deps,
      );
    };

    let ppNpmDependencies = (fmt, deps) => {
      let ppDnf = (ppConstr, fmt, f) => {
        let ppConj = Fmt.(list(~sep=unit(" && "), ppConstr));
        Fmt.(list(~sep=unit(" || "), ppConj))(fmt, f);
      };

      let ppVersionSpec = (fmt, spec) =>
        switch (spec) {
        | VersionSpec.Npm(f) => ppDnf(SemverVersion.Constraint.pp, fmt, f)
        | VersionSpec.NpmDistTag(tag) => Fmt.string(fmt, tag)
        | VersionSpec.Opam(f) =>
          ppDnf(OpamPackageVersion.Constraint.pp, fmt, f)
        | VersionSpec.Source(src) => Fmt.pf(fmt, "%a", SourceSpec.pp, src)
        };

      let ppReq = (fmt, req) =>
        Fmt.fmt("%s@%a", fmt, req.Req.name, ppVersionSpec, req.spec);

      Fmt.pf(
        fmt,
        "@[<hov>[@;%a@;]@]",
        Fmt.list(~sep=Fmt.unit(", "), ppReq),
        deps,
      );
    };

    switch (deps) {
    | InstallManifest.Dependencies.OpamFormula(deps) =>
      ppOpamDependencies(fmt, deps)
    | InstallManifest.Dependencies.NpmFormula(deps) =>
      ppNpmDependencies(fmt, deps)
    };
  };

  let showDependencies = (deps: InstallManifest.Dependencies.t) =>
    Format.asprintf("%a", ppDependencies, deps);

  let (rootDigest, linkDigest) = {
    let manifestDigest = manifest =>
      switch (SolveSpec.eval(solvespec, manifest)) {
      | Ok(dependencies) =>
        Digestv.(add(string(showDependencies(dependencies))))
      | Error(_) =>
        /* this will just invalidate lockfile and thus we will recompute
           solution and handle this error more gracefully */
        Digestv.(add(string("INVALID")))
      };

    (manifestDigest, manifestDigest);
  };

  let digest =
    Resolutions.digest(sandbox.root.resolutions) |> rootDigest(sandbox.root);

  let* digest = {
    let f = (digest, resolution) => {
      let resolution =
        switch (resolution.Resolution.resolution) {
        | SourceOverride({source: Source.Link(_), override: _}) =>
          Some(resolution)
        | SourceOverride(_) => None
        | Version(Version.Source(Source.Link(_))) => Some(resolution)
        | Version(_) => None
        };

      switch (resolution) {
      | None => return(digest)
      | Some(resolution) =>
        switch%bind (
          Resolver.package(
            ~gitUsername=None,
            ~gitPassword=None, /* Doesn't seem to hit git+https. TODO: does it? */
            ~resolution,
            sandbox.resolver,
          )
        ) {
        | Error(_) =>
          errorf("unable to read package: %a", Resolution.pp, resolution)
        | Ok(pkg) => return(linkDigest(pkg, digest))
        }
      };
    };

    RunAsync.List.foldLeft(
      ~f,
      ~init=digest,
      Resolutions.entries(sandbox.resolutions),
    );
  };

  return(digest);
};
