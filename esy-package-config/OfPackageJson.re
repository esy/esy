[@ocaml.warning "-69"]; // Because of dune runtest
type warning = string;

module BuildType = {
  include BuildType;
  include BuildType.AsInPackageJson;
};

module Available = {
  [@deriving of_yojson({strict: false})]
  type t = {
    [@default EsyOpamLibs.AvailablePlatforms.default]
    available: EsyOpamLibs.AvailablePlatforms.t,
  };
};

let available = json => {
  open Run.Syntax;
  let* {available} =
    Json.parseJsonWith(
      Available.of_yojson,
      json,
      /* switch (Available.of_yojson(json)) { */
      /* | Ok({available}) => Ok(available) */
      /* | Error(warning) => Error([warning]) */
      /* }; */
    );
  Run.return(available);
};

module InstallManifestV1 = {
  module EsyPackageJson = {
    [@deriving of_yojson({strict: false})]
    type t = {
      [@default None]
      _dependenciesForNewEsyInstaller: option(NpmFormula.t),
    };
  };

  module Manifest = {
    [@deriving of_yojson({strict: false})]
    type t = {
      [@default None]
      name: option(string),
      [@default None]
      version: option(SemverVersion.Version.t),
      [@default NpmFormula.empty]
      dependencies: NpmFormula.t,
      [@default NpmFormula.empty]
      peerDependencies: NpmFormula.t,
      [@default StringMap.empty]
      optDependencies: StringMap.t(Json.t),
      [@default None]
      esy: option(EsyPackageJson.t),
      [@default None]
      dist: option(dist),
      [@default InstallConfig.empty]
      installConfig: InstallConfig.t,
    }
    and dist = {
      tarball: string,
      shasum: string,
    };
  };

  module ResolutionsOfManifest = {
    [@deriving of_yojson({strict: false})]
    type t = {resolutions: [@default Resolutions.empty] Resolutions.t};
  };

  module DevDependenciesOfManifest = {
    [@deriving of_yojson({strict: false})]
    type t = {
      [@default NpmFormula.empty]
      devDependencies: NpmFormula.t,
    };
  };

  let rebaseDependencies = (source, reqs) => {
    open Run.Syntax;
    let f = req =>
      switch (source, req.Req.spec) {
      | (
          Source.Dist(LocalPath({path: basePath, _})) |
          Source.Link({path: basePath, _}),
          VersionSpec.Source(SourceSpec.LocalPath({path, manifest})),
        ) =>
        let path = DistPath.rebase(~base=basePath, path);
        let spec =
          VersionSpec.Source(SourceSpec.LocalPath({path, manifest}));
        return(Req.make(~name=req.name, ~spec));
      | (_, VersionSpec.Source(SourceSpec.LocalPath(_))) =>
        errorf(
          "path constraints %a are not allowed from %a",
          VersionSpec.pp,
          req.spec,
          Source.pp,
          source,
        )
      | _ => return(req)
      };

    Result.List.map(~f, reqs);
  };

  let ofJson =
      (
        ~parseResolutions,
        ~parseDevDependencies,
        ~source=?,
        ~name,
        ~version,
        json,
      ) => {
    open Run.Syntax;
    let* pkgJson = Json.parseJsonWith(Manifest.of_yojson, json);
    let originalVersion =
      switch (pkgJson.Manifest.version) {
      | Some(version) => Some(Version.Npm(version))
      | None => None
      };

    let* source =
      switch (source, pkgJson.dist) {
      | (Some(source), _) => return(source)
      | (None, Some(dist)) =>
        return(
          Source.Dist(
            Archive({
              url: dist.tarball,
              checksum: (Checksum.Sha1, dist.shasum),
            }),
          ),
        )
      | (None, None) =>
        error("unable to determine package source, missing 'dist' metadata")
      };

    let dependencies =
      switch (pkgJson.esy) {
      | None
      | Some({EsyPackageJson._dependenciesForNewEsyInstaller: None}) =>
        pkgJson.dependencies
      | Some({
          EsyPackageJson._dependenciesForNewEsyInstaller: Some(dependencies),
        }) => dependencies
      };

    let dependencies = {
      let f = req => req.Req.name != "esy";
      List.filter(~f, dependencies);
    };

    let* dependencies = rebaseDependencies(source, dependencies);

    let* devDependencies =
      switch (parseDevDependencies) {
      | false => return(NpmFormula.empty)
      | true =>
        let* {DevDependenciesOfManifest.devDependencies} =
          Json.parseJsonWith(DevDependenciesOfManifest.of_yojson, json);

        let* devDependencies = rebaseDependencies(source, devDependencies);
        return(devDependencies);
      };

    let* resolutions =
      switch (parseResolutions) {
      | false => return(Resolutions.empty)
      | true =>
        let* {ResolutionsOfManifest.resolutions} =
          Json.parseJsonWith(ResolutionsOfManifest.of_yojson, json);

        return(resolutions);
      };

    let source =
      switch (source) {
      | Source.Link({path, manifest, kind}) =>
        PackageSource.Link({path, manifest, kind})
      | Source.Dist(dist) =>
        PackageSource.Install({source: (dist, []), opam: None})
      };

    let warnings = [];

    /********************************************************************/
    /* ----                                                             */
    /* TODO                                                             */
    /* ----                                                             */
    /*                                                                  */
    /* Parse NPM's `cpu` (for cpu architecture) and `os` and persist it */
    /* in the lock file.                                                */
    /*                                                                  */
    /********************************************************************/

    let available = EsyOpamLibs.AvailablePlatforms.default;
    return((
      {
        InstallManifest.name,
        version,
        originalVersion,
        originalName: pkgJson.name,
        overrides: Overrides.empty,
        dependencies: InstallManifest.Dependencies.NpmFormula(dependencies),
        devDependencies:
          InstallManifest.Dependencies.NpmFormula(devDependencies),
        peerDependencies: pkgJson.peerDependencies,
        optDependencies:
          pkgJson.optDependencies |> StringMap.keys |> StringSet.of_list,
        resolutions,
        source,
        kind:
          if (Option.isSome(pkgJson.esy)) {
            Esy;
          } else {
            Npm;
          },
        installConfig: pkgJson.installConfig,
        extraSources: [],
        available,
      },
      warnings,
    ));
  };
};

module BuildManifestV1 = {
  [@deriving of_yojson({strict: false})]
  type packageJson = {
    [@default None]
    name: option(string),
    [@default None]
    version: option(Version.t),
    [@default None]
    esy: option(packageJsonEsy),
  }
  [@deriving of_yojson({strict: false})]
  and packageJsonEsy = {
    build: [@default CommandList.empty] CommandList.t,
    buildDev: [@default None] option(CommandList.t),
    install: [@default CommandList.empty] CommandList.t,
    buildsInSource: [@default BuildType.OutOfSource] BuildType.t,
    exportedEnv: [@default ExportedEnv.empty] ExportedEnv.t,
    buildEnv: [@default BuildEnv.empty] BuildEnv.t,
    sandboxEnv: [@default SandboxEnv.empty] SandboxEnv.t,
  };

  let ofJson = json => {
    open Run.Syntax;
    let* pkgJson = Json.parseJsonWith(packageJson_of_yojson, json);
    switch (pkgJson.esy) {
    | Some(m) =>
      let warnings = [];
      let build = {
        BuildManifest.name: pkgJson.name,
        version: pkgJson.version,
        buildType: m.buildsInSource,
        exportedEnv: m.exportedEnv,
        buildEnv: m.buildEnv,
        build: EsyCommands(m.build),
        buildDev: m.buildDev,
        install: EsyCommands(m.install),
        patches: [],
        substs: [],
      };
      return(Some((build, warnings)));
    | None => return(None)
    };
  };
};

module EsyVersion = {
  type t = int;

  let default = 1;
  let supported = [default];

  let pp = (fmt, version) => Fmt.pf(fmt, "%i.0.0", version);

  let of_yojson = json => {
    open Result.Syntax;
    let* constr = Json.Decode.string(json);
    let* constr = SemverVersion.Formula.parse(constr);
    switch (constr) {
    | [
        [
          SemverVersion.Constraint.EQ({
            SemverVersion.Version.major: v,
            minor: 0,
            patch: 0,
            prerelease: [],
            build: [],
          }),
        ],
      ] =>
      return(v)
    | invalid =>
      errorf(
        {|invalid "esy" version: %a must be one of: %a|},
        SemverVersion.Formula.DNF.pp,
        invalid,
        Fmt.(list(pp)),
        supported,
      )
    };
  };

  module OfPackageJson = {
    type dependencies = {esy: option(t)};

    let dependencies_of_yojson = json =>
      Result.Syntax.(
        switch (json) {
        | `Assoc(items) =>
          let f = ((key, _json)) => key == "esy";
          switch (List.find_opt(~f, items)) {
          | Some((_, json)) =>
            let* esy = of_yojson(json);
            return({esy: Some(esy)});
          | None => return({esy: None})
          };
        | _ => errorf({|reading "dependencies": expected an object|})
        }
      );

    [@deriving of_yojson({strict: false})]
    type manifest = {
      [@default {esy: Some(default)}]
      dependencies,
    };

    let parse = json =>
      switch (Json.parseJsonWith(manifest_of_yojson, json)) {
      | Ok(manifest) => Ok(manifest.dependencies.esy)
      | Error(err) => Error(err)
      };
  };
};

let unknownEsyVersionError = version =>
  Run.errorf(
    {|unsupported "esy" version: %a must be one of: %a|},
    EsyVersion.pp,
    version,
    Fmt.(list(EsyVersion.pp)),
    EsyVersion.supported,
  );

let missingEsyVersionWarning =
  Format.asprintf(
    {|missing "esy" version declaration in "dependencies", assuming it is %a. \
      This version of esy supports the following versions: %a|},
    EsyVersion.pp,
    EsyVersion.default,
    Fmt.(list(EsyVersion.pp)),
    EsyVersion.supported,
  );

let installManifest =
    (
      ~parseResolutions=false,
      ~parseDevDependencies=false,
      ~source=?,
      ~name,
      ~version,
      json,
    ) => {
  open Run.Syntax;
  let* esyVersion = EsyVersion.OfPackageJson.parse(json);
  switch (esyVersion) {
  | Some(1) =>
    InstallManifestV1.ofJson(
      ~parseResolutions,
      ~parseDevDependencies,
      ~source?,
      ~name,
      ~version,
      json,
    )
  | Some(v) => unknownEsyVersionError(v)
  | None =>
    let* (m, warnings) =
      InstallManifestV1.ofJson(
        ~parseResolutions,
        ~parseDevDependencies,
        ~source?,
        ~name,
        ~version,
        json,
      );

    return((m, [missingEsyVersionWarning, ...warnings]));
  };
};

let buildManifest = json => {
  open Run.Syntax;
  let* esyVersion = EsyVersion.OfPackageJson.parse(json);
  switch (esyVersion) {
  | Some(1) => BuildManifestV1.ofJson(json)
  | Some(v) => unknownEsyVersionError(v)
  | None =>
    switch%bind (BuildManifestV1.ofJson(json)) {
    | Some((m, warnings)) =>
      return(Some((m, [missingEsyVersionWarning, ...warnings])))
    | None => return(None)
    }
  };
};
