open EsyPackageConfig;

module PackageCache =
  Memoize.Make({
    type key = (string, Resolution.resolution);
    type value = RunAsync.t(result(InstallManifest.t, string));
  });

module SourceCache =
  Memoize.Make({
    type key = SourceSpec.t;
    type value = RunAsync.t(Source.t);
  });

module ResolutionCache =
  Memoize.Make({
    type key = string;
    type value = RunAsync.t(list(Resolution.t));
  });

let requireOpamName = name =>
  Run.Syntax.(
    switch (Astring.String.cut(~sep="@opam/", name)) {
    | Some(("", name)) => return(OpamPackage.Name.of_string(name))
    | _ => errorf("invalid opam package name: %s", name)
    }
  );

let ensureOpamName = name =>
  Run.Syntax.(
    switch (Astring.String.cut(~sep="@opam/", name)) {
    | Some(("", name)) => return(OpamPackage.Name.of_string(name))
    | Some(_)
    | None => return(OpamPackage.Name.of_string(name))
    }
  );

let toOpamOcamlVersion = version =>
  switch (version) {
  | Some(Version.Npm({major, minor, patch, _})) =>
    let minor =
      if (minor < 10) {
        "0" ++ string_of_int(minor);
      } else {
        string_of_int(minor);
      };

    let patch =
      if (patch < 1000) {
        patch;
      } else {
        patch / 1000;
      };

    let v = Printf.sprintf("%i.%s.%i", major, minor, patch);
    let v =
      switch (OpamPackageVersion.Version.parse(v)) {
      | Ok(v) => v
      | Error(msg) => failwith(msg)
      };

    Some(v);
  | Some(Version.Opam(v)) => Some(v)
  | Some(Version.Source(_)) => None
  | None => None
  };

type t = {
  cfg: Config.t,
  sandbox: EsyFetch.SandboxSpec.t,
  pkgCache: PackageCache.t,
  srcCache: SourceCache.t,
  opamRegistries: list(OpamRegistry.t),
  npmRegistry: NpmRegistry.t,
  mutable ocamlVersion: option(Version.t),
  mutable resolutions: Resolutions.t,
  resolutionCache: ResolutionCache.t,
  resolutionUsage: Hashtbl.t(Resolution.t, bool),
  npmDistTags: Hashtbl.t(string, StringMap.t(SemverVersion.Version.t)),
  sourceSpecToSource: Hashtbl.t(SourceSpec.t, Source.t),
  sourceToSource: Hashtbl.t(Source.t, Source.t),
  gitUsername: option(string),
  gitPassword: option(string),
  os: option(System.Platform.t),
  arch: option(System.Arch.t),
};

let emptyLink = (~name, ~path, ~manifest, ~kind, ()) => {
  InstallManifest.name,
  version: Version.Source(Source.Link({path, manifest, kind})),
  originalVersion: None,
  originalName: None,
  source: PackageSource.Link({path, manifest: None, kind}),
  overrides: Overrides.empty,
  dependencies: InstallManifest.Dependencies.NpmFormula([]),
  devDependencies: InstallManifest.Dependencies.NpmFormula([]),
  peerDependencies: NpmFormula.empty,
  optDependencies: StringSet.empty,
  resolutions: Resolutions.empty,
  kind: Esy,
  installConfig: InstallConfig.empty,
  extraSources: [],
  available: AvailablePlatforms.default,
};

let emptyInstall = (~name, ~source, ()) => {
  InstallManifest.name,
  version: Version.Source(Dist(source)),
  originalVersion: None,
  originalName: None,
  source: PackageSource.Install({source: (source, []), opam: None}),
  overrides: Overrides.empty,
  dependencies: InstallManifest.Dependencies.NpmFormula([]),
  devDependencies: InstallManifest.Dependencies.NpmFormula([]),
  peerDependencies: NpmFormula.empty,
  optDependencies: StringSet.empty,
  resolutions: Resolutions.empty,
  kind: Esy,
  installConfig: InstallConfig.empty,
  extraSources: [],
  available: AvailablePlatforms.default,
};

let make = (~os=?, ~arch=?, ~gitUsername, ~gitPassword, ~cfg, ~sandbox, ()) =>
  RunAsync.return({
    cfg,
    sandbox,
    pkgCache: PackageCache.make(),
    srcCache: SourceCache.make(),
    opamRegistries: OpamRegistries.make(~cfg, ()),
    npmRegistry: NpmRegistry.make(~url=cfg.Config.npmRegistry, ()),
    ocamlVersion: None,
    resolutions: Resolutions.empty,
    resolutionCache: ResolutionCache.make(),
    resolutionUsage: Hashtbl.create(10),
    npmDistTags: Hashtbl.create(500),
    sourceSpecToSource: Hashtbl.create(500),
    sourceToSource: Hashtbl.create(500),
    gitUsername,
    gitPassword,
    os,
    arch,
  });

let setOCamlVersion = (ocamlVersion, resolver) =>
  resolver.ocamlVersion = Some(ocamlVersion);

let setResolutions = (resolutions, resolver) =>
  resolver.resolutions = resolutions;

let getUnusedResolutions = resolver => {
  let nameIfUnused = (usage, resolution: Resolution.t) =>
    switch (Hashtbl.find_opt(usage, resolution)) {
    | Some(true) => None
    | _ => Some(resolution.name)
    };

  List.filter_map(
    ~f=nameIfUnused(resolver.resolutionUsage),
    Resolutions.entries(resolver.resolutions),
  );
};

/* This function increments the resolution usage count of that resolution */
let markResolutionAsUsed = (resolver, resolution) =>
  Hashtbl.replace(resolver.resolutionUsage, resolution, true);

let sourceMatchesSpec = (resolver, spec, source) =>
  switch (Hashtbl.find_opt(resolver.sourceSpecToSource, spec)) {
  | Some(resolvedSource) =>
    if (Source.compare(resolvedSource, source) == 0) {
      true;
    } else {
      switch (Hashtbl.find_opt(resolver.sourceToSource, resolvedSource)) {
      | Some(resolvedSource) => Source.compare(resolvedSource, source) == 0
      | None => false
      };
    }
  | None => false
  };

let versionByNpmDistTag = (resolver: t, package: string, tag: string) =>
  switch (Hashtbl.find_opt(resolver.npmDistTags, package)) {
  | None => None
  | Some(tags) => StringMap.find_opt(tag, tags)
  };

let sourceBySpec = (resolver: t, spec: SourceSpec.t) =>
  switch (Hashtbl.find_opt(resolver.sourceSpecToSource, spec)) {
  | None => None
  | Some(source) =>
    switch (Hashtbl.find_opt(resolver.sourceToSource, source)) {
    | None => Some(source)
    | Some(source) => Some(source)
    }
  };

let versionMatchesReq = (resolver: t, req: Req.t, name, version: Version.t) => {
  let checkVersion = () =>
    switch (req.spec, version) {
    | (VersionSpec.Npm(spec), Version.Npm(version)) =>
      SemverVersion.Formula.DNF.matches(~version, spec)

    | (VersionSpec.NpmDistTag(tag), Version.Npm(version)) =>
      switch (Hashtbl.find_opt(resolver.npmDistTags, req.name)) {
      | Some(tags) =>
        switch (StringMap.find_opt(tag, tags)) {
        | None => false
        | Some(taggedVersion) =>
          SemverVersion.Version.compare(version, taggedVersion) == 0
        }
      | None => false
      }

    | (VersionSpec.Opam(spec), Version.Opam(version)) =>
      OpamPackageVersion.Formula.DNF.matches(~version, spec)

    | (VersionSpec.Source(spec), Version.Source(source)) =>
      sourceMatchesSpec(resolver, spec, source)

    | (VersionSpec.Npm(_), _) => false
    | (VersionSpec.NpmDistTag(_), _) => false
    | (VersionSpec.Opam(_), _) => false
    | (VersionSpec.Source(_), _) => false
    };

  let checkResolutions = () =>
    switch (Resolutions.find(resolver.resolutions, req.name)) {
    | Some(_) => true
    | None => false
    };

  req.name == name && (checkResolutions() || checkVersion());
};

let versionMatchesDep =
    (resolver: t, dep: InstallManifest.Dep.t, name, version: Version.t) => {
  let checkVersion = () =>
    switch (version, dep.InstallManifest.Dep.req) {
    | (Version.Npm(version), Npm(spec)) =>
      SemverVersion.Constraint.matches(~version, spec)

    | (Version.Opam(version), Opam(spec)) =>
      OpamPackageVersion.Constraint.matches(~version, spec)

    | (Version.Source(source), Source(spec)) =>
      sourceMatchesSpec(resolver, spec, source)

    | (Version.Npm(_), _) => false
    | (Version.Opam(_), _) => false
    | (Version.Source(_), _) => false
    };

  let checkResolutions = () =>
    switch (Resolutions.find(resolver.resolutions, dep.name)) {
    | Some(_) => true
    | None => false
    };

  dep.name == name && (checkResolutions() || checkVersion());
};

let ocamlOpamVersionToOcamlNpmVersion = v => {
  let v = OpamPackage.Version.to_string(v);
  let parsed =
    Astring.(
      String.cuts(
        ~sep=".",
        String.trim(
          ~drop=
            fun
            | '~' =>
              /* Note: also drop `~~` from versions:
               * https://opam.ocaml.org/doc/Manual.html
               */
              true
            | c => Char.Ascii.is_white(c),
          v,
        ),
      )
    );
  let npmVersion =
    switch (parsed) {
    | [major, minor, patch] =>
      try({
        let int_patch = int_of_string(patch);
        String.concat(".", [major, minor, string_of_int(int_patch * 1000)]);
      }) {
      | _ => String.concat(".", parsed)
      }
    | other => String.concat(".", other)
    };
  SemverVersion.Version.parse(npmVersion);
};
let convertOpamAtom = ((name, relop): OpamFormula.atom) => {
  open Result.Syntax;
  let name =
    switch (OpamPackage.Name.to_string(name)) {
    | "ocaml" => "ocaml"
    | name => "@opam/" ++ name
    };

  switch (name) {
  | "ocaml" =>
    module C = SemverVersion.Constraint;
    let req =
      switch (relop) {
      | None => return(C.ANY)
      | Some((`Eq, v)) =>
        switch (OpamPackage.Version.to_string(v)) {
        | "broken" => error("package is marked as broken")
        | _ =>
          let* v = ocamlOpamVersionToOcamlNpmVersion(v);
          return(C.EQ(v));
        }
      | Some((`Neq, v)) =>
        let* v = ocamlOpamVersionToOcamlNpmVersion(v);
        return(C.NEQ(v));
      | Some((`Lt, v)) =>
        let* v = ocamlOpamVersionToOcamlNpmVersion(v);
        return(C.LT(v));
      | Some((`Gt, v)) =>
        let* v = ocamlOpamVersionToOcamlNpmVersion(v);
        return(C.GT(v));
      | Some((`Leq, v)) =>
        let* v = ocamlOpamVersionToOcamlNpmVersion(v);
        return(C.LTE(v));
      | Some((`Geq, v)) =>
        let* v = ocamlOpamVersionToOcamlNpmVersion(v);
        return(C.GTE(v));
      };
    let containsSubstring = (subString, s) => {
      Str.string_match(Str.regexp(subString), s, 0);
    };
    let* req =
      switch (req) {
      | Ok(v) => Ok(v)
      | Error(msg) when containsSubstring("invalid semver version: ", msg) =>
        /*************************************************************************/
        /* We encountered packages with constraints like this:                   */
        /*                                                                       */
        /* "ocaml" {>= "4.04.1" & < "5.2.0" & != "5.1.0~alpha1"}                 */
        /*                                                                       */
        /* 5.1.0~alpha1 is not a valid semver tag but needs to be allowed here.  */
        /* TODO: We must try to parse this with an opam lib and make sure semver */
        /* validation fails but is still a valid opam version                    */
        /*************************************************************************/

        return(C.ANY)
      | e => e
      };
    return({InstallManifest.Dep.name, req: Npm(req)});
  | name =>
    module C = OpamPackageVersion.Constraint;
    let req =
      switch (relop) {
      | None => C.ANY
      | Some((`Eq, v)) => C.EQ(v)
      | Some((`Neq, v)) => C.NEQ(v)
      | Some((`Lt, v)) => C.LT(v)
      | Some((`Gt, v)) => C.GT(v)
      | Some((`Leq, v)) => C.LTE(v)
      | Some((`Geq, v)) => C.GTE(v)
      };

    return({InstallManifest.Dep.name, req: Opam(req)});
  };
};

let convertOpamFormula = f => {
  let cnf = OpamFormula.to_cnf(f);
  Result.List.map(~f=Result.List.map(~f=convertOpamAtom), cnf);
};

let convertOpamUrl = manifest => {
  open Result.Syntax;

  let convChecksum = hash =>
    switch (OpamHash.kind(hash)) {
    | `MD5 => (Checksum.Md5, OpamHash.contents(hash))
    | `SHA256 => (Checksum.Sha256, OpamHash.contents(hash))
    | `SHA512 => (Checksum.Sha512, OpamHash.contents(hash))
    };

  let convUrl = (url: OpamUrl.t) =>
    switch (url.backend) {
    | `http => return(OpamUrl.to_string(url))
    | _ =>
      errorf("unsupported dist for opam package: %s", OpamUrl.to_string(url))
    };

  let sourceOfOpamUrl = url => {
    let* hash =
      switch (OpamFile.URL.checksum(url)) {
      | [] =>
        errorf(
          "no checksum provided for %s@%s",
          OpamPackage.Name.to_string(manifest.OpamManifest.name),
          OpamPackage.Version.to_string(manifest.OpamManifest.version),
        )
      | [hash, ..._] => return(hash)
      };

    let mirrors = {
      let urls = [OpamFile.URL.url(url), ...OpamFile.URL.mirrors(url)];

      let f = (mirrors, url) =>
        switch (convUrl(url)) {
        | Ok(url) => [
            Dist.Archive({url, checksum: convChecksum(hash)}),
            ...mirrors,
          ]
        | Error(_) => mirrors
        };

      List.fold_left(~f, ~init=[], urls);
    };

    let main = {
      let url =
        "https://opam.ocaml.org/cache/"
        ++ String.concat("/", OpamHash.to_path(hash));
      Dist.Archive({url, checksum: convChecksum(hash)});
    };

    return((main, mirrors));
  };

  switch (manifest.url) {
  | Some(url) => sourceOfOpamUrl(url)
  | None =>
    let main = Dist.NoSource;
    Ok((main, []));
  };
};
let convOpamKind = kind =>
  switch (kind) {
  | `MD5 => Checksum.Md5
  | `SHA256 => Sha256
  | `SHA512 => Sha512
  };

let opamHashToChecksum = opamHash => {
  let kind = OpamHash.kind(opamHash) |> convOpamKind;
  let contents = OpamHash.contents(opamHash);
  (kind, contents);
};

let convertDependencies = (~os, ~arch, manifest) => {
  open Result.Syntax;

  let filterOpamFormula = (~os, ~arch, ~build, ~post, ~test, ~doc, ~dev, f) => {
    let f = {
      let env = var => {
        switch (OpamVariable.Full.to_string(var)) {
        | "test" => Some(OpamVariable.B(test))
        | "doc" => Some(OpamVariable.B(doc))
        | "with-test" => Some(OpamVariable.B(test))
        | "with-dev-setup" => Some(OpamVariable.B(dev))
        | "with-doc" => Some(OpamVariable.B(doc))
        | "dev" => Some(OpamVariable.B(dev))
        | "arch" =>
          switch (arch) {
          | Some(arch) => Some(OpamVariable.S(System.Arch.show(arch)))
          | None => None
          }
        | "os" =>
          switch (os) {
          | Some(os) =>
            open System.Platform;
            // We could have avoided the following altogether if the System.Platform implementation
            // matched opam's. TODO
            let sys =
              switch (os) {
              | Darwin => "macos"
              | Linux => "linux"
              | Cygwin => "cygwin"
              | Unix => "unix"
              | Windows => "win32"
              | Unknown => "unknown"
              };
            Some(OpamVariable.S(sys));
          | None => None
          }
        | "version" =>
          let version =
            OpamPackage.Version.to_string(manifest.OpamManifest.version);
          Some(OpamVariable.S(version));
        | _ => None
        };
      };

      OpamFilter.partial_filter_formula(env, f);
    };

    try(
      return(
        OpamFilter.filter_deps(
          ~default=true,
          ~build,
          ~post,
          ~test,
          ~doc,
          ~dev,
          f,
        ),
      )
    ) {
    | Failure(msg) => Error(msg)
    };
  };

  let filterAndConvertOpamFormula = (~os, ~build, ~post, ~test, ~doc, ~dev, f) => {
    let* f =
      filterOpamFormula(~os, ~arch, ~build, ~post, ~test, ~doc, ~dev, f);
    convertOpamFormula(f);
  };

  /*
   *  post=false since PR#1319
   *  See: https://github.com/esy/esy/pull/1319
   */
  let* dependencies = {
    let* formula =
      filterAndConvertOpamFormula(
        ~os,
        ~build=true,
        ~post=false,
        ~test=false,
        ~doc=false,
        ~dev=false,
        OpamFile.OPAM.depends(manifest.opam),
      );

    let esySubstsDep = {
      InstallManifest.Dep.name: "@esy-ocaml/substs",
      req: Npm(SemverVersion.Constraint.ANY),
    };

    let formula = formula @ [[esySubstsDep]];

    return(InstallManifest.Dependencies.OpamFormula(formula));
  };

  let* devDependencies = {
    let* formula =
      filterAndConvertOpamFormula(
        ~os,
        ~build=false,
        ~post=false,
        ~test=true,
        ~doc=true,
        ~dev=true,
        OpamFile.OPAM.depends(manifest.OpamManifest.opam),
      );
    return(InstallManifest.Dependencies.OpamFormula(formula));
  };

  let* optDependencies = {
    let* formula =
      filterOpamFormula(
        ~os,
        ~arch,
        ~build=false,
        ~post=false,
        ~test=true,
        ~doc=true,
        ~dev=true,
        OpamFile.OPAM.depopts(manifest.OpamManifest.opam),
      );

    return(
      formula
      |> OpamFormula.atoms
      |> List.map(~f=((name, _)) =>
           "@opam/" ++ OpamPackage.Name.to_string(name)
         )
      |> StringSet.of_list,
    );
  };

  let extraSources =
    manifest.opam
    |> OpamFile.OPAM.extra_sources
    |> List.map(~f=((basename, u)) => {
         let relativePath = OpamFilename.Base.to_string(basename);
         let url = OpamUrl.to_string(OpamFile.URL.url(u));
         let checksum =
           OpamFile.URL.checksum(u) |> List.hd |> opamHashToChecksum;

         {ExtraSource.url, relativePath, checksum};
       });

  let availableFilter = OpamFile.OPAM.available(manifest.opam);
  let available =
    AvailablePlatforms.default |> AvailablePlatforms.filter(availableFilter);

  return((
    dependencies,
    devDependencies,
    optDependencies,
    extraSources,
    available,
  ));
};

let opamManifestToInstallManifest =
    (~source=?, ~os, ~arch, ~name, ~version, manifest) => {
  open RunAsync.Syntax;

  let converted = {
    open Result.Syntax;
    let* source = convertOpamUrl(manifest);
    let* (
      dependencies,
      devDependencies,
      optDependencies,
      extraSources,
      available,
    ) =
      convertDependencies(~os, ~arch, manifest);
    return((
      source,
      dependencies,
      devDependencies,
      optDependencies,
      extraSources,
      available,
    ));
  };

  switch (converted) {
  | Error(err) => return(Error(err))
  | Ok((
      sourceFromOpam,
      dependencies,
      devDependencies,
      optDependencies,
      extraSources,
      available,
    )) =>
    let opam =
      switch (manifest.opamRepositoryPath) {
      | Some(path) =>
        Some(OpamResolution.make(manifest.name, manifest.version, path))
      | None => None
      };

    let source =
      switch (source) {
      | None => PackageSource.Install({source: sourceFromOpam, opam})
      | Some(Source.Link({path, manifest, kind})) =>
        Link({path, manifest, kind})
      | Some(Source.Dist(source)) => Install({source: (source, []), opam})
      };

    let overrides =
      switch (manifest.override) {
      | None => Overrides.empty
      | Some(override) => Overrides.(add(override, empty))
      };

    return(
      Ok({
        InstallManifest.name,
        version,
        originalVersion: None,
        originalName: None,
        kind: InstallManifest.Esy,
        source,
        overrides,
        dependencies,
        devDependencies,
        optDependencies,
        peerDependencies: NpmFormula.empty,
        resolutions: Resolutions.empty,
        installConfig: InstallConfig.empty,
        extraSources,
        available,
      }),
    );
  };
};
let packageOfSource = (~name, ~overrides, source: Source.t, resolver) => {
  open RunAsync.Syntax;

  let readManifest =
      (
        ~name,
        ~source,
        {EsyFetch.DistResolver.kind, filename: _, data, suggestedPackageName},
      ) =>
    RunAsync.Syntax.(
      switch (kind) {
      | ManifestSpec.Esy =>
        let* (manifest, _warnings) =
          RunAsync.ofRun(
            {
              open Run.Syntax;
              let* json = Json.parse(data);
              OfPackageJson.installManifest(
                ~parseResolutions=true,
                ~parseDevDependencies=true,
                ~name,
                ~version=Version.Source(source),
                ~source,
                json,
              );
            },
          );
        return(Ok(manifest));
      | ManifestSpec.Opam =>
        let* opamname = RunAsync.ofRun(ensureOpamName(suggestedPackageName));
        let* manifest =
          RunAsync.ofRun(
            {
              let version = OpamPackage.Version.of_string("dev");
              OpamManifest.ofString(~name=opamname, ~version, data);
            },
          );
        opamManifestToInstallManifest(
          ~os=resolver.os,
          ~arch=resolver.arch,
          ~name,
          ~version=Version.Source(source),
          ~source,
          manifest,
        );
      }
    );

  let pkg = {
    let* {EsyFetch.DistResolver.overrides, dist: resolvedDist, manifest, _} =
      EsyFetch.DistResolver.resolve(
        ~gitUsername=resolver.gitUsername,
        ~gitPassword=resolver.gitPassword,
        ~cfg=resolver.cfg.installCfg,
        ~sandbox=resolver.sandbox,
        ~overrides,
        ~pkgName=name,
        Source.toDist(source),
      );

    let* resolvedSource =
      switch (source, resolvedDist) {
      | (Source.Dist(_), _) => return(Source.Dist(resolvedDist))
      | (Source.Link({kind, _}), Dist.LocalPath({path, manifest})) =>
        return(Source.Link({path, manifest, kind}))
      | (Source.Link(_), dist) =>
        errorf("unable to link to %a", Dist.pp, dist)
      };

    let* pkg =
      switch (manifest) {
      | Some(manifest) =>
        readManifest(~name, ~source=resolvedSource, manifest)
      | None =>
        if (!Overrides.isEmpty(overrides)) {
          switch (source) {
          | Source.Link({path, manifest, kind}) =>
            let pkg = emptyLink(~name, ~path, ~manifest, ~kind, ());
            return(Ok(pkg));
          | _ =>
            let pkg = emptyInstall(~name, ~source=resolvedDist, ());
            return(Ok(pkg));
          };
        } else {
          errorf("no manifest found at %a", Source.pp, source);
        }
      };

    let pkg =
      switch (pkg) {
      | Ok(pkg) => Ok({...pkg, InstallManifest.overrides})
      | err => err
      };

    Hashtbl.replace(resolver.sourceToSource, source, resolvedSource);

    return(pkg);
  };

  RunAsync.contextf(
    pkg,
    "reading package metadata from %a",
    Source.ppPretty,
    source,
  );
};

let applyOverride = (pkg, override: Override.install) => {
  let {Override.dependencies, devDependencies, resolutions} = override;

  let applyNpmFormulaOverride = (dependencies, override) =>
    switch (dependencies) {
    | InstallManifest.Dependencies.NpmFormula(formula) =>
      let formula = {
        let dependencies = {
          let f = (map, req) => StringMap.add(req.Req.name, req, map);
          List.fold_left(~f, ~init=StringMap.empty, formula);
        };

        let dependencies = StringMap.Override.apply(dependencies, override);

        StringMap.values(dependencies);
      };

      InstallManifest.Dependencies.NpmFormula(formula);
    | InstallManifest.Dependencies.OpamFormula(formula) =>
      /* remove all terms which we override */
      let formula = {
        let filter = dep =>
          switch (StringMap.find_opt(dep.InstallManifest.Dep.name, override)) {
          | None => true
          | Some(_) => false
          };

        formula
        |> List.map(~f=List.filter(~f=filter))
        |> List.filter(
             ~f=
               fun
               | [] => false
               | _ => true,
           );
      };

      /* now add all edits */
      let formula = {
        let edits = {
          let f = (_name, override, edits) =>
            switch (override) {
            | StringMap.Override.Drop => edits
            | StringMap.Override.Edit(req) =>
              switch (req.Req.spec) {
              | VersionSpec.Npm(formula) =>
                let f = (c: SemverVersion.Constraint.t) => {
                  InstallManifest.Dep.name: req.name,
                  req: Npm(c),
                };

                let formula = SemverVersion.Formula.ofDnfToCnf(formula);
                List.map(~f=List.map(~f), formula) @ edits;
              | VersionSpec.Opam(formula) =>
                let f = (c: OpamPackageVersion.Constraint.t) => {
                  InstallManifest.Dep.name: req.name,
                  req: Opam(c),
                };

                List.map(~f=List.map(~f), formula) @ edits;
              | VersionSpec.NpmDistTag(_) =>
                failwith("cannot override opam with npm dist tag")
              | VersionSpec.Source(spec) => [
                  [{InstallManifest.Dep.name: req.name, req: Source(spec)}],
                  ...edits,
                ]
              }
            };

          StringMap.fold(f, override, []);
        };

        formula @ edits;
      };

      InstallManifest.Dependencies.OpamFormula(formula);
    };

  let pkg =
    switch (dependencies) {
    | Some(override) => {
        ...pkg,
        InstallManifest.dependencies:
          applyNpmFormulaOverride(pkg.InstallManifest.dependencies, override),
      }
    | None => pkg
    };

  let pkg =
    switch (devDependencies) {
    | Some(override) => {
        ...pkg,
        InstallManifest.devDependencies:
          applyNpmFormulaOverride(
            pkg.InstallManifest.devDependencies,
            override,
          ),
      }
    | None => pkg
    };

  let pkg =
    switch (resolutions) {
    | Some(resolutions) =>
      let resolutions = {
        let f = Resolutions.add;
        StringMap.fold(f, resolutions, Resolutions.empty);
      };

      {...pkg, InstallManifest.resolutions};
    | None => pkg
    };

  pkg;
};

let package = (~resolution: Resolution.t, resolver) => {
  open RunAsync.Syntax;
  let key = (resolution.name, resolution.resolution);

  let ofVersion = (~override=?, version: Version.t) => {
    let patch_overrides = (pkg: InstallManifest.t) =>
      switch (override) {
      | Some(override) => {
          ...pkg,
          overrides: Overrides.add(override, pkg.overrides),
        }
      | None => pkg
      };
    switch (version) {
    | Version.Npm(version) =>
      let* pkg =
        NpmRegistry.package(
          ~name=resolution.name,
          ~version,
          resolver.npmRegistry,
          (),
        );
      let pkg = patch_overrides(pkg);
      return(Ok(pkg));
    | Version.Opam(version) =>
      switch%bind (
        {
          let* name = RunAsync.ofRun(requireOpamName(resolution.name));
          let rec aux = opamRegistries => {
            switch (opamRegistries) {
            | [] => RunAsync.return(None)
            | [opamRegistry, ...opamRegistries] =>
              let%lwt version =
                OpamRegistry.version(~name, ~version, opamRegistry);
              switch (version) {
              | Error(e) =>
                opamRegistries == []
                  ? Lwt.return(Error(e)) : aux(opamRegistries)
              | Ok(version) => Lwt.return(Ok(version))
              };
            };
          };
          aux(resolver.opamRegistries);
        }
      ) {
      | Some(manifest) =>
        let* pkg_result =
          opamManifestToInstallManifest(
            ~os=resolver.os,
            ~arch=resolver.arch,
            ~name=resolution.name,
            ~version=Version.Opam(version),
            manifest,
          );
        return(Result.map(~f=patch_overrides, pkg_result));
      | None => errorf("no such opam package: %a", Resolution.pp, resolution)
      }
    | Version.Source(source) =>
      packageOfSource(
        ~overrides=Overrides.empty,
        ~name=resolution.name,
        source,
        resolver,
      )
    };
  };

  PackageCache.compute(
    resolver.pkgCache,
    key,
    _ => {
      let* pkg =
        switch (resolution.resolution) {
        | VersionOverride({version, override: None}) => ofVersion(version)
        | VersionOverride({version, override: Some(override)}) =>
          let override = Override.ofJson(override);
          ofVersion(~override, version);
        | SourceOverride({source, override}) =>
          let override = Override.ofJson(override);
          let overrides = Overrides.(add(override, empty));
          packageOfSource(
            ~name=resolution.name,
            ~overrides,
            source,
            resolver,
          );
        };

      switch (pkg) {
      | Ok(pkg) =>
        let* pkg =
          Overrides.foldWithInstallOverrides(
            ~f=applyOverride,
            ~init=pkg,
            pkg.overrides,
          );

        return(Ok(pkg));
      | err => return(err)
      };
    },
  );
};

let resolveSource = (~name, ~sourceSpec: SourceSpec.t, resolver: t) => {
  open RunAsync.Syntax;

  let gitConfig =
    switch (resolver.gitUsername, resolver.gitPassword) {
    | (Some(gitUsername), Some(gitPassword)) => [
        (
          "credential.helper",
          Printf.sprintf(
            "!f() { sleep 1; echo username=%s; echo password=%s; }; f",
            gitUsername,
            gitPassword,
          ),
        ),
      ]
    | _ => []
    };
  let errorResolvingSource = msg =>
    errorf(
      "unable to resolve %s@%a: %s",
      name,
      SourceSpec.pp,
      sourceSpec,
      msg,
    );

  SourceCache.compute(
    resolver.srcCache,
    sourceSpec,
    _ => {
      let%lwt () =
        Esy_logs_lwt.debug(m =>
          m("resolving %s@%a", name, SourceSpec.pp, sourceSpec)
        );
      let* source =
        switch (sourceSpec) {
        | SourceSpec.Github({user, repo, ref, manifest}) =>
          let remote =
            Printf.sprintf("https://github.com/%s/%s.git", user, repo);
          let* commit = Git.lsRemote(~config=gitConfig, ~ref?, ~remote, ());
          switch (commit, ref) {
          | (Some(commit), _) =>
            return(Source.Dist(Github({user, repo, commit, manifest})))
          | (None, Some(ref)) =>
            if (Git.isCommitLike(ref)) {
              return(
                Source.Dist(Github({user, repo, commit: ref, manifest})),
              );
            } else {
              errorResolvingSource("cannot resolve commit");
            }
          | (None, None) => errorResolvingSource("cannot resolve commit")
          };

        | SourceSpec.Git({remote, ref, manifest}) =>
          let* commit = Git.lsRemote(~config=gitConfig, ~ref?, ~remote, ());
          switch (commit, ref) {
          | (Some(commit), _) =>
            return(Source.Dist(Git({remote, commit, manifest})))
          | (None, Some(ref)) =>
            if (Git.isCommitLike(ref)) {
              return(Source.Dist(Git({remote, commit: ref, manifest})));
            } else {
              errorResolvingSource("cannot resolve commit");
            }
          | (None, None) => errorResolvingSource("cannot resolve commit")
          };

        | SourceSpec.NoSource => return(Source.Dist(NoSource))

        | SourceSpec.Archive({url, checksum: None}) =>
          failwith(
            "archive sources without checksums are not implemented: " ++ url,
          )
        | SourceSpec.Archive({url, checksum: Some(checksum)}) =>
          return(Source.Dist(Archive({url, checksum})))

        | SourceSpec.LocalPath({path, manifest}) =>
          let abspath = DistPath.toPath(resolver.sandbox.path, path);
          if%bind (Fs.exists(abspath)) {
            return(Source.Dist(LocalPath({path, manifest})));
          } else {
            errorf("path '%a' does not exist", Path.ppPretty, abspath);
          };
        };

      Hashtbl.replace(resolver.sourceSpecToSource, sourceSpec, source);
      return(source);
    },
  );
};

let resolve' = (~fullMetadata, ~name, ~spec, resolver) =>
  RunAsync.Syntax.(
    switch (spec) {
    | VersionSpec.Npm(_)
    | VersionSpec.NpmDistTag(_) =>
      let* resolutions =
        switch%bind (
          NpmRegistry.versions(~fullMetadata, ~name, resolver.npmRegistry, ())
        ) {
        | Some({NpmRegistry.versions, distTags}) =>
          Hashtbl.replace(resolver.npmDistTags, name, distTags);

          let resolutions = {
            let f = version => {
              let version = Version.Npm(version);
              {
                Resolution.name,
                resolution: VersionOverride({version, override: None}),
              };
            };

            List.map(~f, versions);
          };

          return(resolutions);

        | None => return([])
        };

      let resolutions = {
        let tryCheckConformsToSpec = resolution =>
          switch (resolution.Resolution.resolution) {
          | VersionOverride({version, override: _}) =>
            versionMatchesReq(
              resolver,
              Req.make(~name, ~spec),
              resolution.name,
              version,
            )
          | SourceOverride(_) => true
          }; /* do not filter them out yet */

        resolutions
        |> List.sort(~cmp=(a, b) => Resolution.compare(b, a))
        |> List.filter(~f=tryCheckConformsToSpec);
      };

      return(resolutions);

    | VersionSpec.Opam(_) =>
      let* resolutions =
        ResolutionCache.compute(
          resolver.resolutionCache,
          name,
          () => {
            let%lwt () =
              Esy_logs_lwt.debug(m =>
                m("resolving %s %a", name, VersionSpec.pp, spec)
              );
            let* versions = {
              let* name = RunAsync.ofRun(requireOpamName(name));
              let* f =
                RunAsync.return(
                  OpamRegistry.versions(
                    ~os=?resolver.os,
                    ~arch=?resolver.arch,
                    ~ocamlVersion=?toOpamOcamlVersion(resolver.ocamlVersion),
                    ~name,
                  ),
                );
              List.fold_left(
                ~f=
                  (versions, opamRegistry) => {
                    let* versions = versions;
                    let* versions' = f(opamRegistry);
                    RunAsync.return(versions @ versions');
                  },
                ~init=RunAsync.return([]),
                resolver.opamRegistries,
              );
            };

            let f = (resolution: OpamResolution.t) => {
              let version = OpamResolution.version(resolution);
              {
                Resolution.name,
                resolution: VersionOverride({version, override: None}),
              };
            };

            return(List.map(~f, versions));
          },
        );

      let resolutions = {
        let tryCheckConformsToSpec = resolution =>
          switch (resolution.Resolution.resolution) {
          | VersionOverride({version, override: _}) =>
            versionMatchesReq(
              resolver,
              Req.make(~name, ~spec),
              resolution.name,
              version,
            )
          | SourceOverride(_) => true
          }; /* do not filter them out yet */

        resolutions
        |> List.sort(~cmp=(a, b) => Resolution.compare(b, a))
        |> List.filter(~f=tryCheckConformsToSpec);
      };

      return(resolutions);

    | VersionSpec.Source(sourceSpec) =>
      let* source = resolveSource(~name, ~sourceSpec, resolver);
      let version = Version.Source(source);
      let resolution = {
        Resolution.name,
        resolution: VersionOverride({version, override: None}),
      };
      return([resolution]);
    }
  );

let resolve =
    (
      ~fullMetadata=false,
      ~name: string,
      ~spec: option(VersionSpec.t)=?,
      resolver: t,
    ) =>
  RunAsync.Syntax.(
    switch (Resolutions.find(resolver.resolutions, name)) {
    | Some(resolution) =>
      /* increment usage counter for that resolution so that we know it was used */
      markResolutionAsUsed(resolver, resolution);
      return([resolution]);
    | None =>
      let spec =
        switch (spec) {
        | None =>
          if (InstallManifest.isOpamPackageName(name)) {
            VersionSpec.Opam([[OpamPackageVersion.Constraint.ANY]]);
          } else {
            VersionSpec.Npm([[SemverVersion.Constraint.ANY]]);
          }
        | Some(spec) => spec
        };

      resolve'(~fullMetadata, ~name, ~spec, resolver);
    }
  );

let getResolutions = (resolver: t) => resolver.resolutions;
let getVersionByResolutions = (resolver: t, name) => {
  switch (Resolutions.find(resolver.resolutions, name)) {
  | Some({
      resolution: VersionOverride({version: Version.Source(source), _}),
      _,
    })
  | Some({resolution: SourceOverride({source, _}), _}) =>
    switch (Hashtbl.find_opt(resolver.sourceToSource, source)) {
    | Some(source) => Some(Version.Source(source))
    | None => Some(Version.Source(source))
    }
  | Some({resolution: VersionOverride({version, _}), _}) => Some(version)
  | None => None
  };
};
