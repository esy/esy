open EsyPackageConfig;

module Dependencies = InstallManifest.Dependencies;

module CudfName: {
  type t;

  let make: string => t;
  let encode: string => t;
  let decode: t => string;
  let show: t => string;
  let pp: Fmt.t(t);
} = {
  type t = string;

  let escapeWith = "UuU";
  let underscoreRe = Re.(compile(char('_')));
  let underscoreEscapeRe = Re.(compile(str(escapeWith)));

  let make = name => name;
  let encode = name => Re.replace_string(underscoreRe, ~by=escapeWith, name);
  let decode = name => Re.replace_string(underscoreEscapeRe, ~by="_", name);
  let show = name => name;
  let pp = Fmt.string;
};

type t = {
  pkgs: StringMap.t(Version.Map.t(InstallManifest.t)),
  resolver: Resolver.t,
};

type univ = t;

let empty = resolver => {pkgs: StringMap.empty, resolver};

let add = (~pkg, univ: t) => {
  let {InstallManifest.name, version, _} = pkg;
  let versions =
    switch (StringMap.find_opt(name, univ.pkgs)) {
    | None => Version.Map.empty
    | Some(versions) => versions
    };

  let pkgs =
    StringMap.add(name, Version.Map.add(version, pkg, versions), univ.pkgs);
  {...univ, pkgs};
};

let mem = (~pkg, univ: t) =>
  switch (StringMap.find(pkg.InstallManifest.name, univ.pkgs)) {
  | None => false
  | Some(versions) => Version.Map.mem(pkg.InstallManifest.version, versions)
  };

let findVersion = (~name, ~version, univ: t) =>
  switch (StringMap.find(name, univ.pkgs)) {
  | None => None
  | Some(versions) => Version.Map.find_opt(version, versions)
  };

let findVersionExn = (~name, ~version, univ: t) =>
  switch (findVersion(~name, ~version, univ)) {
  | Some(pkg) => pkg
  | None =>
    let msg =
      Printf.sprintf(
        "inconsistent state: package not in the universr %s@%s",
        name,
        Version.show(version),
      );

    failwith(msg);
  };

let findVersions = (~name, univ: t) =>
  switch (StringMap.find(name, univ.pkgs)) {
  | None => []
  | Some(versions) =>
    versions |> Version.Map.bindings |> List.map(~f=((_, pkg)) => pkg)
  };

module CudfVersionMap: {
  type t;

  let make: (~size: int=?, unit) => t;
  let update: (t, string, Version.t, int) => unit;
  let pkgSize: (t, string) => int;
  let findVersion:
    (~cudfName: CudfName.t, ~cudfVersion: int, t) => option(Version.t);
  let findVersionExn:
    (~cudfName: CudfName.t, ~cudfVersion: int, t) => Version.t;
  let findCudfVersion: (~name: string, ~version: Version.t, t) => option(int);
  let findCudfVersionExn: (~name: string, ~version: Version.t, t) => int;
} = {
  type t = {
    cudfVersionToVersion: Hashtbl.t((CudfName.t, int), Version.t),
    versionToCudfVersion: Hashtbl.t((string, Version.t), int),
    versions: Hashtbl.t(string, Version.Set.t),
  };

  let make = (~size=100, ()) => {
    cudfVersionToVersion: Hashtbl.create(size),
    versionToCudfVersion: Hashtbl.create(size),
    versions: Hashtbl.create(size),
  };

  let update = (map, name, version, cudfVersion) => {
    Hashtbl.replace(map.versionToCudfVersion, (name, version), cudfVersion);
    Hashtbl.replace(
      map.cudfVersionToVersion,
      (CudfName.encode(name), cudfVersion),
      version,
    );
    let () = {
      let versions =
        try (Hashtbl.find(map.versions, name)) {
        | _ => Version.Set.empty
        };

      let versions = Version.Set.add(version, versions);
      Hashtbl.replace(map.versions, name, versions);
    };

    ();
  };

  let pkgSize = (map, name) =>
    Hashtbl.find(map.versions, name) |> Version.Set.elements |> List.length;

  let findVersion = (~cudfName, ~cudfVersion, map) =>
    switch (Hashtbl.find(map.cudfVersionToVersion, (cudfName, cudfVersion))) {
    | exception Not_found => None
    | version => Some(version)
    };

  let findCudfVersion = (~name, ~version, map) =>
    switch (Hashtbl.find(map.versionToCudfVersion, (name, version))) {
    | exception Not_found => None
    | version => Some(version)
    };

  let findVersionExn = (~cudfName: CudfName.t, ~cudfVersion, map) =>
    switch (findVersion(~cudfName, ~cudfVersion, map)) {
    | Some(v) => v
    | None =>
      let msg =
        Format.asprintf(
          "inconsistent state: found a package not in the cudf version map %a@cudf:%i\n",
          CudfName.pp,
          cudfName,
          cudfVersion,
        );

      failwith(msg);
    };

  let findCudfVersionExn = (~name, ~version, map) =>
    switch (findCudfVersion(~name, ~version, map)) {
    | Some(v) => v
    | None =>
      let msg =
        Printf.sprintf(
          "inconsistent state: found a package not in the cudf version map %s@%s",
          name,
          Version.show(version),
        );

      failwith(msg);
    };
};

module CudfMapping = {
  type t = (univ, Cudf.universe, CudfVersionMap.t);

  let encodePkgName = CudfName.encode;
  let decodePkgName = CudfName.decode;

  let decodePkg = (cudf: Cudf.package, (univ, _cudfUniv, vmap)) => {
    let cudfName = CudfName.make(cudf.package);
    let name = CudfName.decode(cudfName);
    switch (
      CudfVersionMap.findVersion(~cudfName, ~cudfVersion=cudf.version, vmap)
    ) {
    | Some(version) => findVersion(~name, ~version, univ)
    | None => None
    };
  };

  let decodePkgExn = (cudf: Cudf.package, (univ, _cudfUniv, vmap)) => {
    let cudfName = CudfName.make(cudf.package);
    let name = CudfName.decode(cudfName);
    let version =
      CudfVersionMap.findVersionExn(
        ~cudfName,
        ~cudfVersion=cudf.version,
        vmap,
      );
    findVersionExn(~name, ~version, univ);
  };

  let encodePkg = (pkg: InstallManifest.t, (_univ, cudfUniv, vmap)) => {
    let name = pkg.name;
    let cudfName = CudfName.encode(pkg.name);
    switch (CudfVersionMap.findCudfVersion(~name, ~version=pkg.version, vmap)) {
    | Some(cudfVersion) =>
      try (
        Some(
          Cudf.lookup_package(
            cudfUniv,
            (CudfName.show(cudfName), cudfVersion),
          ),
        )
      ) {
      | Not_found => None
      }
    | None => None
    };
  };

  let encodePkgExn = (pkg: InstallManifest.t, (_univ, cudfUniv, vmap)) => {
    let name = pkg.name;
    let cudfName = CudfName.encode(pkg.name);
    let cudfVersion =
      CudfVersionMap.findCudfVersionExn(~name, ~version=pkg.version, vmap);
    Cudf.lookup_package(cudfUniv, (CudfName.show(cudfName), cudfVersion));
  };

  let _encodeDepExn = (~name, ~matches, (univ, _cudfUniv, vmap)) => {
    let versions = findVersions(~name, univ);

    let versionsMatched = List.filter(~f=matches, versions);

    switch (versionsMatched) {
    | [] => [
        (CudfName.show(CudfName.encode(name)), Some((`Eq, 100000000))),
      ]
    | versionsMatched =>
      let pkgToConstraint = pkg => {
        let cudfVersion =
          CudfVersionMap.findCudfVersionExn(
            ~name=pkg.InstallManifest.name,
            ~version=pkg.InstallManifest.version,
            vmap,
          );

        (
          CudfName.show(CudfName.encode(pkg.InstallManifest.name)),
          Some((`Eq, cudfVersion)),
        );
      };

      List.map(~f=pkgToConstraint, versionsMatched);
    };
  };

  let univ = ((univ, _, _)) => univ;
  let cudfUniv = ((_, cudfUniv, _)) => cudfUniv;
};

let toCudf = (~installed=InstallManifest.Set.empty, solvespec, univ) => {
  let cudfUniv = Cudf.empty_universe();
  let cudfVersionMap = CudfVersionMap.make();

  let buildVersionMap = () => {
    let allVersions = ref(StringMap.empty);
    let sourceVersions = ref(StringMap.empty);

    let addVersion = (name, version) => {
      let versions =
        switch (StringMap.find_opt(name, allVersions^)) {
        | Some(versions) => versions
        | None => Version.Set.empty
        };
      switch (StringMap.find_opt(name, sourceVersions^)) {
      | Some(_) =>
        failwith("Conflict: source & normal version. TODO: better reporting")
      | None =>
        allVersions :=
          StringMap.add(
            name,
            Version.Set.add(version, versions),
            allVersions^,
          )
      };
    };

    let addSourceVersion = (name, source: Source.t) =>
      switch (StringMap.find_opt(name, allVersions^)) {
      | Some(_) =>
        failwith("Conflict: source & normal version. TODO: better reporting")
      | None =>
        switch (StringMap.find_opt(name, sourceVersions^)) {
        | Some(source') =>
          if (Source.compare(source, source') != 0) {
            failwith(
              "different source versions for one package. TODO: better reporting",
            );
          }
        | None =>
          sourceVersions := StringMap.add(name, source, sourceVersions^)
        }
      };

    let addNpmConstraint = (name, constr: SemverVersion.Constraint.t) =>
      switch (constr) {
      | EQ(version)
      | NEQ(version)
      | GT(version)
      | GTE(version)
      | LT(version)
      | LTE(version) => addVersion(name, Version.Npm(version))
      | ANY => ()
      };

    let addOpamConstraint = (name, constr: OpamPackageVersion.Constraint.t) =>
      switch (constr) {
      | EQ(version)
      | NEQ(version)
      | GT(version)
      | GTE(version)
      | LT(version)
      | LTE(version) => addVersion(name, Version.Opam(version))
      | ANY => ()
      };

    let addNpmDistTag = (name, tag) =>
      switch (Resolver.versionByNpmDistTag(univ.resolver, name, tag)) {
      | None => failwith("invalid npm-dist-tag, TODO: better error reporting")
      | Some(version) => addNpmConstraint(name, EQ(version))
      };

    let addSourcePackage = (name, spec: SourceSpec.t) =>
      switch (Resolver.sourceBySpec(univ.resolver, spec)) {
      | None =>
        failwith("cannot find source by spec, TODO: better error reporting")
      | Some(source) => addSourceVersion(name, source)
      };

    StringMap.iter(
      (name, versions) =>
        Version.Map.iter(
          (version, pkg) => {
            addVersion(name, version);
            let dependencies: Dependencies.t =
              switch (SolveSpec.eval(solvespec, pkg)) {
              | Error(err) =>
                Exn.failf("CUDF encoding error: %a", Run.ppError, err)
              | Ok(dependencies) => dependencies
              };
            switch (dependencies) {
            | Dependencies.OpamFormula(deps) =>
              List.flatten(deps)
              |> List.iter(~f=(dep: InstallManifest.Dep.t) =>
                   switch (dep.req) {
                   | Npm(constr) => addNpmConstraint(dep.name, constr)
                   | NpmDistTag(tag) => addNpmDistTag(dep.name, tag)
                   | Opam(constr) => addOpamConstraint(dep.name, constr)
                   | Source(spec) => addSourcePackage(dep.name, spec)
                   }
                 )
            | Dependencies.NpmFormula(reqs) =>
              List.iter(
                ~f=
                  (req: Req.t) =>
                    switch (req.spec) {
                    | VersionSpec.Npm(dep) =>
                      List.flatten(dep)
                      |> List.iter(~f=addNpmConstraint(req.name))
                    | VersionSpec.NpmDistTag(tag) =>
                      addNpmDistTag(req.name, tag)
                    | VersionSpec.Opam(dep) =>
                      List.flatten(dep)
                      |> List.iter(~f=addOpamConstraint(req.name))
                    | VersionSpec.Source(spec) =>
                      addSourcePackage(req.name, spec)
                    },
                reqs,
              )
            };
            ();
          },
          versions,
        ),
      univ.pkgs,
    );

    StringMap.iter(
      (name, versions) => {
        let f = (cudfVersion, version) =>
          CudfVersionMap.update(
            cudfVersionMap,
            name,
            version,
            cudfVersion + 1,
          );

        List.iteri(~f, Version.Set.elements(versions));
      },
      allVersions^,
    );

    StringMap.iter(
      (name, source) =>
        CudfVersionMap.update(
          cudfVersionMap,
          name,
          Version.Source(source),
          1,
        ),
      sourceVersions^,
    );
  };

  let encodeOpamDep = (dep: InstallManifest.Dep.t) => {
    let v = (constr, version) => (
      dep.name,
      Some((
        constr,
        CudfVersionMap.findCudfVersionExn(
          ~name=dep.name,
          ~version,
          cudfVersionMap,
        ),
      )),
    );
    switch (dep.req) {
    | Npm(req) =>
      switch (req) {
      | EQ(version) => v(`Eq, Npm(version))
      | NEQ(version) => v(`Neq, Npm(version))
      | GT(version) => v(`Gt, Npm(version))
      | GTE(version) => v(`Geq, Npm(version))
      | LT(version) => v(`Lt, Npm(version))
      | LTE(version) => v(`Leq, Npm(version))
      | ANY => (dep.name, None)
      }
    | NpmDistTag(tag) =>
      switch (Resolver.versionByNpmDistTag(univ.resolver, dep.name, tag)) {
      | None =>
        failwith("cannot resolve npm-dist-tag, TODO: better reporting")
      | Some(version) => v(`Eq, Npm(version))
      }
    | Opam(odep) =>
      switch (odep) {
      | EQ(version) => v(`Eq, Opam(version))
      | NEQ(version) => v(`Neq, Opam(version))
      | GT(version) => v(`Gt, Opam(version))
      | GTE(version) => v(`Geq, Opam(version))
      | LT(version) => v(`Lt, Opam(version))
      | LTE(version) => v(`Leq, Opam(version))
      | ANY => (dep.name, None)
      }
    | Source(spec) =>
      switch (Resolver.sourceBySpec(univ.resolver, spec)) {
      | None =>
        failwith("Cannot locate source by spec, TODO: better reporting")
      | Some(source) => v(`Eq, Source(source))
      }
    };
  };

  let encodeNpmReq = (req: Req.t) => {
    switch (req.spec) {
    | Npm(dep) =>
      let v = (constr, version) => (
        req.name,
        Some((
          constr,
          CudfVersionMap.findCudfVersionExn(
            ~name=req.name,
            ~version=Version.Npm(version),
            cudfVersionMap,
          ),
        )),
      );
      let encConstr = (constr: SemverVersion.Constraint.t) =>
        switch (constr) {
        | EQ(version) => v(`Eq, version)
        | NEQ(version) => v(`Neq, version)
        | GT(version) => v(`Gt, version)
        | GTE(version) => v(`Geq, version)
        | LT(version) => v(`Lt, version)
        | LTE(version) => v(`Leq, version)
        | ANY => (req.name, None)
        };
      let rec encOr = ands =>
        switch (ands) {
        | [] => [[]]
        | [[], ...rest] => encOr(rest)
        | [expr, ...rest] =>
          let rest = encOr(rest);
          List.fold_left(
            ~f=
              (acc, constr) =>
                acc
                @ List.map(~f=expr => [encConstr(constr), ...expr], rest),
            ~init=[],
            expr,
          );
        };
      encOr(dep);

    | NpmDistTag(tag) =>
      switch (Resolver.versionByNpmDistTag(univ.resolver, req.name, tag)) {
      | None =>
        failwith("cannot resolve npm-dist-tag, TODO: better reporting")
      | Some(version) =>
        let version =
          CudfVersionMap.findCudfVersionExn(
            ~name=req.name,
            ~version=Version.Npm(version),
            cudfVersionMap,
          );
        [[(req.name, Some((`Eq, version)))]];
      }

    | Opam(dep) =>
      let v = (constr, version) => (
        req.name,
        Some((
          constr,
          CudfVersionMap.findCudfVersionExn(
            ~name=req.name,
            ~version=Version.Opam(version),
            cudfVersionMap,
          ),
        )),
      );
      let encConstr = (constr: OpamPackageVersion.Constraint.t) =>
        switch (constr) {
        | EQ(version) => v(`Eq, version)
        | NEQ(version) => v(`Neq, version)
        | GT(version) => v(`Gt, version)
        | GTE(version) => v(`Geq, version)
        | LT(version) => v(`Lt, version)
        | LTE(version) => v(`Leq, version)
        | ANY => (req.name, None)
        };
      let rec encOr = ands =>
        switch (ands) {
        | [] => [[]]
        | [[], ...rest] => encOr(rest)
        | [expr, ...rest] =>
          let rest = encOr(rest);
          List.fold_left(
            ~f=
              (acc, constr) =>
                acc
                @ List.map(~f=expr => [encConstr(constr), ...expr], rest),
            ~init=[],
            expr,
          );
        };
      encOr(dep);
    | Source(spec) =>
      switch (Resolver.sourceBySpec(univ.resolver, spec)) {
      | None =>
        failwith("Cannot locate source by spec, TODO: better reporting")
      | Some(source) =>
        let version =
          CudfVersionMap.findCudfVersionExn(
            ~name=req.name,
            ~version=Version.Source(source),
            cudfVersionMap,
          );
        [[(req.name, Some((`Eq, version)))]];
      }
    };
  };

  // returns CNF:
  // - inner lists are OR-ed
  // - outer lists are AND-ed
  let encodeDeps = (deps: Dependencies.t) =>
    switch (deps) {
    | OpamFormula(deps) =>
      // deps is CNF
      let f = List.map(~f=encodeOpamDep);
      List.map(~f, deps);
    | NpmFormula(reqs) =>
      // reqs is CNF

      /* Only considering packages which have esy.json / esy config */
      let reqs = {
        let f = (req: Req.t) => StringMap.mem(req.name, univ.pkgs);
        List.filter(~f, reqs);
      };

      // one req is DNF
      List.fold_left(
        ~f=(acc, req) => acc @ encodeNpmReq(req),
        ~init=[],
        reqs,
      );
    };

  let encodePkg = (pkg: InstallManifest.t) => {
    let cudfVersion =
      CudfVersionMap.findCudfVersionExn(
        ~name=pkg.name,
        ~version=pkg.version,
        cudfVersionMap,
      );

    let pkgSize = CudfVersionMap.pkgSize(cudfVersionMap, pkg.name);

    let dependencies =
      switch (SolveSpec.eval(solvespec, pkg)) {
      | Error(err) => Exn.failf("CUDF encoding error: %a", Run.ppError, err)
      | Ok(dependencies) => dependencies
      };

    let depends = encodeDeps(dependencies);
    let staleness = pkgSize - cudfVersion;
    let cudfName = CudfName.encode(pkg.name);
    let cudfPkg = {
      ...Cudf.default_package,
      package: CudfName.show(cudfName),
      version: cudfVersion,
      conflicts: [(CudfName.show(cudfName), None)],
      installed: InstallManifest.Set.mem(pkg, installed),
      pkg_extra: [
        ("staleness", `Int(staleness)),
        ("original-version", `String(Version.show(pkg.version))),
      ],
      depends,
    };

    Cudf.add_package(cudfUniv, cudfPkg);
  };

  /* find all versions of the package */

  buildVersionMap();

  StringMap.iter(
    (name, _) => findVersions(~name, univ) |> List.iter(~f=encodePkg),
    univ.pkgs,
  );

  (cudfUniv, (univ, cudfUniv, cudfVersionMap));
};
