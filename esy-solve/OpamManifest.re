open EsyPackageConfig;

let esySubstsDep = {
  InstallManifest.Dep.name: "@esy-ocaml/substs",
  req: Npm(SemverVersion.Constraint.ANY),
};

module File = {
  module Cache =
    Memoize.Make({
      type key = Path.t;
      type value = RunAsync.t(OpamFile.OPAM.t);
    });

  let ofString = (~upgradeIfOpamVersionIsLessThan=?, ~filename=?, data) => {
    let filename = {
      let filename = Option.orDefault(~default="opam", filename);
      OpamFile.make(OpamFilename.of_string(filename));
    };

    let opam = OpamFile.OPAM.read_from_string(~filename, data);
    switch (upgradeIfOpamVersionIsLessThan) {
    | Some(upgradeIfOpamVersionIsLessThan) =>
      let opamVersion = OpamFile.OPAM.opam_version(opam);
      if (OpamVersion.compare(opamVersion, upgradeIfOpamVersionIsLessThan) < 0) {
        OpamFormatUpgrade.opam_file(~filename, opam);
      } else {
        opam;
      };
    | None => opam
    };
  };

  let ofPath = (~upgradeIfOpamVersionIsLessThan=?, ~cache=?, path) => {
    open RunAsync.Syntax;
    let load = () => {
      let* data = Fs.readFile(path);
      let filename = Path.show(path);
      return(ofString(~upgradeIfOpamVersionIsLessThan?, ~filename, data));
    };

    switch (cache) {
    | Some(cache) => Cache.compute(cache, path, load)
    | None => load()
    };
  };
};

type t = {
  name: OpamPackage.Name.t,
  version: OpamPackage.Version.t,
  opam: OpamFile.OPAM.t,
  url: option(OpamFile.URL.t),
  override: option(Override.t),
  opamRepositoryPath: option(Path.t),
};

let ofPath = (~name, ~version, path: Path.t) => {
  open RunAsync.Syntax;
  let* opam = File.ofPath(path);
  return({
    name,
    version,
    opamRepositoryPath: Some(Path.parent(path)),
    opam,
    url: None,
    override: None,
  });
};

let ofString = (~name, ~version, data: string) => {
  open Run.Syntax;
  let opam = File.ofString(data);
  return({
    name,
    version,
    opam,
    url: None,
    opamRepositoryPath: None,
    override: None,
  });
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
    let* req =
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

let convertOpamUrl = (manifest: t) => {
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
          OpamPackage.Name.to_string(manifest.name),
          OpamPackage.Version.to_string(manifest.version),
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

let convertDependencies = manifest => {
  open Result.Syntax;

  let filterOpamFormula = (~build, ~post, ~test, ~doc, ~dev, f) => {
    let f = {
      let env = var => {
        switch (OpamVariable.Full.to_string(var)) {
        | "test" => Some(OpamVariable.B(test))
        | "doc" => Some(OpamVariable.B(doc))
        | "with-test" => Some(OpamVariable.B(test))
        | "with-doc" => Some(OpamVariable.B(doc))
        | "dev" => Some(OpamVariable.B(dev))
        | "version" =>
          let version = OpamPackage.Version.to_string(manifest.version);
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

  let filterAndConvertOpamFormula = (~build, ~post, ~test, ~doc, ~dev, f) => {
    let* f = filterOpamFormula(~build, ~post, ~test, ~doc, ~dev, f);
    convertOpamFormula(f);
  };

  let* dependencies = {
    let* formula =
      filterAndConvertOpamFormula(
        ~build=true,
        ~post=false,
        ~test=false,
        ~doc=false,
        ~dev=false,
        OpamFile.OPAM.depends(manifest.opam),
      );

    let formula = formula @ [[esySubstsDep]];

    return(InstallManifest.Dependencies.OpamFormula(formula));
  };

  let* devDependencies = {
    let* formula =
      filterAndConvertOpamFormula(
        ~build=false,
        ~post=false,
        ~test=true,
        ~doc=true,
        ~dev=true,
        OpamFile.OPAM.depends(manifest.opam),
      );
    return(InstallManifest.Dependencies.OpamFormula(formula));
  };

  let* optDependencies = {
    let* formula =
      filterOpamFormula(
        ~build=false,
        ~post=false,
        ~test=true,
        ~doc=true,
        ~dev=true,
        OpamFile.OPAM.depopts(manifest.opam),
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

  return((dependencies, devDependencies, optDependencies));
};

let toInstallManifest = (~source=?, ~name, ~version, manifest) => {
  open RunAsync.Syntax;

  let converted = {
    open Result.Syntax;
    let* source = convertOpamUrl(manifest);
    let* (dependencies, devDependencies, optDependencies) =
      convertDependencies(manifest);
    return((source, dependencies, devDependencies, optDependencies));
  };

  switch (converted) {
  | Error(err) => return(Error(err))
  | Ok((sourceFromOpam, dependencies, devDependencies, optDependencies)) =>
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
      }),
    );
  };
};
