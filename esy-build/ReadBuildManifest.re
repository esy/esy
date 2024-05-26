open EsyPackageConfig;

let ofPackageJson = (path: Path.t) => {
  open RunAsync.Syntax;
  let* json = Fs.readJsonFile(path);
  switch (OfPackageJson.buildManifest(json)) {
  | Ok(Some(manifest)) =>
    return((Some(manifest), Path.Set.singleton(path)))
  | Ok(None) => return((None, Path.Set.empty))
  | Error(err) => Lwt.return(Error(err))
  };
};

let applyOverride = (manifest: BuildManifest.t, override: Override.build) => {
  let {
    Override.buildType,
    build,
    buildDev,
    install,
    exportedEnv,
    exportedEnvOverride,
    buildEnv,
    buildEnvOverride,
  } = override;

  let manifest =
    switch (buildType) {
    | None => manifest
    | Some(buildType) => {...manifest, buildType}
    };

  let manifest =
    switch (build) {
    | None => manifest
    | Some(commands) => {...manifest, build: EsyCommands(commands)}
    };

  let manifest =
    switch (buildDev) {
    | None => manifest
    | commands => {...manifest, buildDev: commands}
    };

  let manifest =
    switch (install) {
    | None => manifest
    | Some(commands) => {...manifest, install: EsyCommands(commands)}
    };

  let manifest =
    switch (exportedEnv) {
    | None => manifest
    | Some(exportedEnv) => {...manifest, exportedEnv}
    };

  let manifest =
    switch (exportedEnvOverride) {
    | None => manifest
    | Some(override) => {
        ...manifest,
        exportedEnv: StringMap.Override.apply(manifest.exportedEnv, override),
      }
    };

  let manifest =
    switch (buildEnv) {
    | None => manifest
    | Some(buildEnv) => {...manifest, buildEnv}
    };

  let manifest =
    switch (buildEnvOverride) {
    | None => manifest
    | Some(override) => {
        ...manifest,
        buildEnv: StringMap.Override.apply(manifest.buildEnv, override),
      }
    };

  manifest;
};

let parseOpam = data =>
  Run.Syntax.(
    if (String.trim(data) == "") {
      return(None);
    } else {
      let* opam =
        try(return(OpamFile.OPAM.read_from_string(data))) {
        | Failure(msg) => errorf("error parsing opam: %s", msg)
        | _ => errorf(" error parsing opam")
        };

      return(Some(opam));
    }
  );

let ensurehasOpamScope = name =>
  switch (Astring.String.cut(~sep="@opam/", name)) {
  | Some(("", _)) => name
  | Some(_)
  | None => "@opam/" ++ name
  };

module OpamBuild = {
  let buildOfOpam = (~name, ~version, opam: OpamFile.OPAM.t) => {
    let build = BuildManifest.OpamCommands(OpamFile.OPAM.build(opam));
    let install = BuildManifest.OpamCommands(OpamFile.OPAM.install(opam));

    let patches = {
      let patches = OpamFile.OPAM.patches(opam);
      let f = ((name, filter)) => {
        let name = Path.v(OpamFilename.Base.to_string(name));
        (name, filter);
      };

      List.map(~f, patches);
    };

    let substs = {
      let names = OpamFile.OPAM.substs(opam);
      let f = name => Path.v(OpamFilename.Base.to_string(name));
      List.map(~f, names);
    };

    let name =
      switch (name) {
      | Some(name) => Some(ensurehasOpamScope(name))
      | None => None
      };

    {
      BuildManifest.name,
      version,
      buildType: BuildType.InSource,
      exportedEnv: ExportedEnv.empty,
      buildEnv: BuildEnv.empty,
      build,
      buildDev: None,
      install,
      patches,
      substs,
    };
  };

  let ofData = (~nameFallback, data) => {
    open Run.Syntax;
    switch%bind (parseOpam(data)) {
    | None => return(None)
    | Some(opam) =>
      let name =
        try(Some(OpamPackage.Name.to_string(OpamFile.OPAM.name(opam)))) {
        | _ => nameFallback
        };

      let version =
        try(Some(Version.Opam(OpamFile.OPAM.version(opam)))) {
        | _ => None
        };

      let warnings = [];
      return(Some((buildOfOpam(~name, ~version, opam), warnings)));
    };
  };

  let ofFile = (path: Path.t) => {
    open RunAsync.Syntax;
    let* data = Fs.readFile(path);
    switch (ofData(~nameFallback=None, data)) {
    | Ok(None) => errorf("unable to load opam manifest at %a", Path.pp, path)
    | Ok(Some(manifest)) =>
      return((Some(manifest), Path.Set.singleton(path)))
    | Error(err) => Lwt.return(Error(err))
    };
  };
};

let discoverManifest = (path, pkgName) => {
  open RunAsync.Syntax;

  let* filenames = ManifestDiscovery.discover(path, pkgName);

  let filenames = List.map(~f=((a, b)) => (a, Path.show(b)), filenames);

  let rec tryLoad =
    fun
    | [] => return((None, Path.Set.empty))
    | [(kind, fname), ...rest] => {
        let%lwt () =
          Esy_logs_lwt.debug(m =>
            m("trying %a %a", Path.pp, path, ManifestSpec.pp, (kind, fname))
          );
        let fname = Path.(path / fname);
        if%bind (Fs.exists(fname)) {
          switch (kind) {
          | ManifestSpec.Esy => ofPackageJson(fname)
          | ManifestSpec.Opam => OpamBuild.ofFile(fname)
          };
        } else {
          tryLoad(rest);
        };
      };

  tryLoad(filenames);
};

let ofPath = (~manifest=?, path: Path.t, pkgName) => {
  let%lwt () =
    Esy_logs_lwt.debug(m =>
      m(
        "ReadBuildManifest.ofPath %a %a",
        Fmt.(option(ManifestSpec.pp)),
        manifest,
        Path.pp,
        path,
      )
    );

  let manifest =
    switch (manifest) {
    | None => discoverManifest(path, pkgName)
    | Some(spec) =>
      switch (spec) {
      | (ManifestSpec.Esy, fname) =>
        let path = Path.(path / Filename.basename(fname));
        ofPackageJson(path);
      | (ManifestSpec.Opam, fname) =>
        let path = Path.(path / Filename.basename(fname));
        OpamBuild.ofFile(path);
      }
    };

  RunAsync.contextf(
    manifest,
    "reading package metadata from %a",
    Path.ppPretty,
    path,
  );
};

let ofInstallationLocation =
    (
      spec,
      installCfg,
      pkg: EsyFetch.Package.t,
      loc: EsyFetch.Installation.location,
    ) =>
  RunAsync.Syntax.(
    switch (pkg.source) {
    | Link({path, manifest, kind: _}) =>
      let dist = Dist.LocalPath({path, manifest});
      let* res =
        EsyFetch.DistResolver.resolve(
          ~gitUsername=None,
          ~gitPassword=None,
          ~cfg=installCfg,
          ~sandbox=spec,
          dist,
          ~pkgName=pkg.name,
        ); /* Git creds are None. Since link resolutions are local, git creds (which are only used over HTTPS) are not needed */

      let overrides =
        Overrides.merge(pkg.overrides, res.EsyFetch.DistResolver.overrides);
      let* manifest =
        switch (res.EsyFetch.DistResolver.manifest) {
        | Some({
            kind: ManifestSpec.Esy,
            filename: _,
            data,
            suggestedPackageName: _,
          }) =>
          RunAsync.ofRun(
            {
              open Run.Syntax;
              let* json = Json.parse(data);
              OfPackageJson.buildManifest(json);
            },
          )
        | Some({
            kind: ManifestSpec.Opam,
            filename: _,
            data,
            suggestedPackageName,
          }) =>
          RunAsync.ofRun(
            OpamBuild.ofData(~nameFallback=Some(suggestedPackageName), data),
          )
        | None =>
          let manifest = BuildManifest.empty(~name=None, ~version=None, ());
          return(Some((manifest, [])));
        };

      switch (manifest) {
      | None =>
        if (Overrides.isEmpty(overrides)) {
          return((None, res.EsyFetch.DistResolver.paths));
        } else {
          let manifest = BuildManifest.empty(~name=None, ~version=None, ());
          let* manifest =
            Overrides.foldWithBuildOverrides(
              ~f=applyOverride,
              ~init=manifest,
              overrides,
            );

          return((Some(manifest), res.EsyFetch.DistResolver.paths));
        }
      | Some((manifest, _warnings)) =>
        let* manifest =
          Overrides.foldWithBuildOverrides(
            ~f=applyOverride,
            ~init=manifest,
            overrides,
          );

        return((Some(manifest), res.EsyFetch.DistResolver.paths));
      };

    | Install({source: (source, _), opam: _}) =>
      switch%bind (EsyFetch.Package.opam(pkg)) {
      | Some((name, version, opamfile)) =>
        let manifest =
          OpamBuild.buildOfOpam(
            ~name=Some(name),
            ~version=Some(version),
            opamfile,
          );

        let* manifest =
          Overrides.foldWithBuildOverrides(
            ~f=applyOverride,
            ~init=manifest,
            pkg.overrides,
          );

        return((Some(manifest), Path.Set.empty));
      | None =>
        let manifest = Dist.manifest(source);
        let* (manifest, paths) = ofPath(~manifest?, loc, pkg.name);
        let* manifest =
          switch (manifest) {
          | Some((manifest, _warnings)) =>
            let* manifest =
              Overrides.foldWithBuildOverrides(
                ~f=applyOverride,
                ~init=manifest,
                pkg.overrides,
              );

            return(Some(manifest));
          | None =>
            if (Overrides.isEmpty(pkg.overrides)) {
              return(None);
            } else {
              let manifest =
                BuildManifest.empty(~name=None, ~version=None, ());
              let* manifest =
                Overrides.foldWithBuildOverrides(
                  ~f=applyOverride,
                  ~init=manifest,
                  pkg.overrides,
                );

              return(Some(manifest));
            }
          };

        return((manifest, paths));
      }
    }
  );
