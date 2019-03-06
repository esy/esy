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
  let addPackageVersions: (list(InstallManifest.t), t) => unit;

  let findVersion:
    (~cudfName: CudfName.t, ~cudfVersion: int, t) => option(Version.t);
  let findVersionExn:
    (~cudfName: CudfName.t, ~cudfVersion: int, t) => Version.t;

  let findCudfVersion: (~name: string, ~version: Version.t, t) => option(int);
  let findCudfVersionExn: (~name: string, ~version: Version.t, t) => int;

  let findCudfNeighborhood:
    (string, Version.t, t) => (option(int), option(int), option(int));
} = {
  module IntMap =
    Map.Make({
      type t = int;
      let compare = (a, b) => a - b;
    });

  type mapping = {
    mutable toCudf: Version.Map.t(int),
    mutable ofCudf: IntMap.t(Version.t),
  };

  type t = {
    packages: Hashtbl.t(string, mapping),
    cudfVersionToVersion: Hashtbl.t((CudfName.t, int), Version.t),
    versionToCudfVersion: Hashtbl.t((string, Version.t), int),
    versions: Hashtbl.t(string, Version.Set.t),
  };

  let make = (~size=100, ()) => {
    packages: Hashtbl.create(size),
    cudfVersionToVersion: Hashtbl.create(size),
    versionToCudfVersion: Hashtbl.create(size),
    versions: Hashtbl.create(size),
  };

  let getMapping = (name, vmap) => {
    switch (Hashtbl.find_opt(vmap.packages, name)) {
    | Some(mapping) => mapping
    | None =>
      let mapping = {toCudf: Version.Map.empty, ofCudf: IntMap.empty};
      Hashtbl.replace(vmap.packages, name, mapping);
      mapping;
    };
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

    let () = {
      let mapping = getMapping(name, map);
      mapping.toCudf = Version.Map.add(version, cudfVersion, mapping.toCudf);
      mapping.ofCudf = IntMap.add(cudfVersion, version, mapping.ofCudf);
    };

    ();
  };

  let maxVersionsPerPackage = 10000000;

  let addPackageVersions = (pkgVersions: list(InstallManifest.t), map) => {
    // sort versions first
    let pkgVersions = {
      let cmp = (a, b) => {
        Version.compare(a.InstallManifest.version, b.InstallManifest.version);
      };
      List.sort(~cmp, pkgVersions);
    };
    let f = (index, pkg: InstallManifest.t) => {
      let cudfVersion =
        switch (pkg.version) {
        | Npm(_)
        | Opam(_) => index + 1
        | Source(_) => index + maxVersionsPerPackage + 1
        };
      update(map, pkg.name, pkg.version, cudfVersion);
    };

    List.iteri(~f, pkgVersions);
  };

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

  let findCudfNeighborhood = (name, version, vmap) => {
    let mapping = getMapping(name, vmap);
    let (prev, this, next) = Version.Map.split(version, mapping.toCudf);
    let prev =
      switch (Version.Map.max_binding_opt(prev)) {
      | None => None
      | Some((_, v)) => Some(v)
      };
    let next =
      switch (Version.Map.min_binding_opt(next)) {
      | None => None
      | Some((_, v)) =>
        if (v < maxVersionsPerPackage) {
          Some(v);
        } else {
          None;
        }
      };
    (prev, this, next);
  };
};

module CudfMapping = {
  type t = {
    univ,
    cudfUniv: Cudf.universe,
    versionMap: CudfVersionMap.t,
  };

  let encodePkgName = CudfName.encode;
  let decodePkgName = CudfName.decode;

  let decodePkg = (cudf: Cudf.package, mapping) => {
    let cudfName = CudfName.make(cudf.package);
    let name = CudfName.decode(cudfName);
    switch (
      CudfVersionMap.findVersion(
        ~cudfName,
        ~cudfVersion=cudf.version,
        mapping.versionMap,
      )
    ) {
    | Some(version) => findVersion(~name, ~version, mapping.univ)
    | None => None
    };
  };

  let decodePkgExn = (cudf: Cudf.package, mapping) => {
    let cudfName = CudfName.make(cudf.package);
    let name = CudfName.decode(cudfName);
    let version =
      CudfVersionMap.findVersionExn(
        ~cudfName,
        ~cudfVersion=cudf.version,
        mapping.versionMap,
      );
    findVersionExn(~name, ~version, mapping.univ);
  };

  let encodePkg = (pkg: InstallManifest.t, mapping) => {
    let name = pkg.name;
    let cudfName = CudfName.encode(pkg.name);
    try (
      {
        let cudfVersion =
          CudfVersionMap.findCudfVersionExn(
            ~name,
            ~version=pkg.version,
            mapping.versionMap,
          );
        Some(
          Cudf.lookup_package(
            mapping.cudfUniv,
            (CudfName.show(cudfName), cudfVersion),
          ),
        );
      }
    ) {
    | Not_found => None
    };
  };

  let encodePkgExn = (pkg: InstallManifest.t, mapping) => {
    let name = pkg.name;
    let cudfName = CudfName.encode(pkg.name);
    let cudfVersion =
      CudfVersionMap.findCudfVersionExn(
        ~name,
        ~version=pkg.version,
        mapping.versionMap,
      );
    Cudf.lookup_package(
      mapping.cudfUniv,
      (CudfName.show(cudfName), cudfVersion),
    );
  };

  let encodeDepExn = (~name, ~matches, mapping) => {
    let versions = findVersions(~name, mapping.univ);

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
            mapping.versionMap,
          );

        (
          CudfName.show(CudfName.encode(pkg.InstallManifest.name)),
          Some((`Eq, cudfVersion)),
        );
      };

      List.map(~f=pkgToConstraint, versionsMatched);
    };
  };

  let encodeOpamDep = (~matchExactly, dep: InstallManifest.Dep.t, mapping) => {
    let versions = findVersions(~name=dep.name, mapping.univ);
    let toCudfName = name => CudfName.show(CudfName.encode(name));

    let findCudfNeighborhood = v =>
      CudfVersionMap.findCudfNeighborhood(dep.name, v, mapping.versionMap);

    // TODO: think of something better here
    let forceConflict = [(toCudfName(dep.name), Some((`Eq, 100000000)))];

    switch (dep.req) {
    // opam constraints
    | Opam(OpamPackageVersion.Constraint.ANY) => [
        (toCudfName(dep.name), None),
      ]
    | Opam(OpamPackageVersion.Constraint.NONE) => [
        (toCudfName(dep.name), None),
      ]
    | Opam(OpamPackageVersion.Constraint.EQ(v)) =>
      switch (findCudfNeighborhood(Version.Opam(v))) {
      | (_, Some(v), _) => [(toCudfName(dep.name), Some((`Eq, v)))]
      | (_, None, _) => forceConflict
      }
    | Opam(OpamPackageVersion.Constraint.NEQ(v)) =>
      switch (findCudfNeighborhood(Version.Opam(v))) {
      | (_, Some(v), _) => [(toCudfName(dep.name), Some((`Neq, v)))]
      | (_, None, _) => []
      }
    | Opam(OpamPackageVersion.Constraint.LT(v)) =>
      switch (findCudfNeighborhood(Version.Opam(v))) {
      | (_, Some(v), _) => [(toCudfName(dep.name), Some((`Lt, v)))]
      | (_, None, Some(v)) => [(toCudfName(dep.name), Some((`Lt, v)))]
      | (_, None, None) => forceConflict
      }
    | Opam(OpamPackageVersion.Constraint.LTE(v)) =>
      switch (findCudfNeighborhood(Version.Opam(v))) {
      | (_, Some(v), _) => [(toCudfName(dep.name), Some((`Lte, v)))]
      | (_, None, Some(v)) => [(toCudfName(dep.name), Some((`Lt, v)))]
      | (_, None, None) => forceConflict
      }
    | Opam(OpamPackageVersion.Constraint.GT(v)) =>
      switch (findCudfNeighborhood(Version.Opam(v))) {
      | (_, Some(v), _) => [(toCudfName(dep.name), Some((`Gt, v)))]
      | (Some(v), None, _) => [(toCudfName(dep.name), Some((`Gt, v)))]
      | (None, None, _) => forceConflict
      }
    | Opam(OpamPackageVersion.Constraint.GTE(v)) =>
      switch (findCudfNeighborhood(Version.Opam(v))) {
      | (_, Some(v), _) => [(toCudfName(dep.name), Some((`Gte, v)))]
      | (Some(v), None, _) => [(toCudfName(dep.name), Some((`Gt, v)))]
      | (None, None, _) => forceConflict
      }
    // npm constraints
    | Npm(SemverVersion.Constraint.ANY) => [(toCudfName(dep.name), None)]
    | Npm(SemverVersion.Constraint.NONE) => [(toCudfName(dep.name), None)]
    | Npm(SemverVersion.Constraint.EQ(v)) =>
      switch (findCudfNeighborhood(Version.Npm(v))) {
      | (_, Some(v), _) => [(toCudfName(dep.name), Some((`Eq, v)))]
      | (_, None, _) => forceConflict
      }
    | Npm(SemverVersion.Constraint.NEQ(v)) =>
      switch (findCudfNeighborhood(Version.Npm(v))) {
      | (_, Some(v), _) => [(toCudfName(dep.name), Some((`Neq, v)))]
      | (_, None, _) => []
      }
    | Npm(SemverVersion.Constraint.LT(v)) =>
      switch (findCudfNeighborhood(Version.Npm(v))) {
      | (_, Some(v), _) => [(toCudfName(dep.name), Some((`Lt, v)))]
      | (_, None, Some(v)) => [(toCudfName(dep.name), Some((`Lt, v)))]
      | (_, None, None) => forceConflict
      }
    | Npm(SemverVersion.Constraint.LTE(v)) =>
      switch (findCudfNeighborhood(Version.Npm(v))) {
      | (_, Some(v), _) => [(toCudfName(dep.name), Some((`Lte, v)))]
      | (_, None, Some(v)) => [(toCudfName(dep.name), Some((`Lt, v)))]
      | (_, None, None) => forceConflict
      }
    | Npm(SemverVersion.Constraint.GT(v)) =>
      switch (findCudfNeighborhood(Version.Npm(v))) {
      | (_, Some(v), _) => [(toCudfName(dep.name), Some((`Gt, v)))]
      | (Some(v), None, _) => [(toCudfName(dep.name), Some((`Gt, v)))]
      | (None, None, _) => forceConflict
      }
    | Npm(SemverVersion.Constraint.GTE(v)) =>
      switch (findCudfNeighborhood(Version.Npm(v))) {
      | (_, Some(v), _) => [(toCudfName(dep.name), Some((`Gte, v)))]
      | (Some(v), None, _) => [(toCudfName(dep.name), Some((`Gt, v)))]
      | (None, None, _) => forceConflict
      }
    // we compare those exactly
    | NpmDistTag(_)
    | Source(_) =>
      let versionsMatched = List.filter(~f=matchExactly(dep), versions);

      switch (versionsMatched) {
      | [] => forceConflict
      | versionsMatched =>
        let pkgToConstraint = pkg => {
          let cudfVersion =
            CudfVersionMap.findCudfVersionExn(
              ~name=pkg.InstallManifest.name,
              ~version=pkg.InstallManifest.version,
              mapping.versionMap,
            );

          (
            CudfName.show(CudfName.encode(pkg.InstallManifest.name)),
            Some((`Eq, cudfVersion)),
          );
        };

        List.map(~f=pkgToConstraint, versionsMatched);
      };
    };
  };

  let encodeNpmReq = (~matchExactly, req: Req.t, mapping) => {
    let versions = findVersions(~name=req.name, mapping.univ);
    let toCudfName = name => CudfName.show(CudfName.encode(name));

    let findCudfNeighborhood = v =>
      CudfVersionMap.findCudfNeighborhood(req.name, v, mapping.versionMap);

    // TODO: think of something better here
    let forceConflict = [(toCudfName(req.name), Some((`Eq, 100000000)))];

    switch (req.spec) {
    // opam constraints
    | Opam(formula) => []
    | Npm(formula) =>
      let formula = SemverVersion.Formula.ofDnfToCnf(formula);
      [];
    // we compare those exactly
    | NpmDistTag(_)
    | Source(_) =>
      let versionsMatched = List.filter(~f=matchExactly(req), versions);

      switch (versionsMatched) {
      | [] => forceConflict
      | versionsMatched =>
        let pkgToConstraint = pkg => {
          let cudfVersion =
            CudfVersionMap.findCudfVersionExn(
              ~name=pkg.InstallManifest.name,
              ~version=pkg.InstallManifest.version,
              mapping.versionMap,
            );

          (
            CudfName.show(CudfName.encode(pkg.InstallManifest.name)),
            Some((`Eq, cudfVersion)),
          );
        };

        List.map(~f=pkgToConstraint, versionsMatched);
      };
    };
  };

  let univ = mapping => mapping.univ;
  let cudfUniv = mapping => mapping.cudfUniv;
};

let toCudf = (~installed=InstallManifest.Set.empty, solvespec, univ) => {
  let cudfUniv = Cudf.empty_universe();
  let versionMap = CudfVersionMap.make();

  /* We add packages in batch by name so this "set of package names" is
   * enough to check if we have handled a pkg already.
   */
  let (seen, markAsSeen) = {
    let names = ref(StringSet.empty);
    let seen = name => StringSet.mem(name, names^);
    let markAsSeen = name => names := StringSet.add(name, names^);
    (seen, markAsSeen);
  };

  let encodeOpamDep = (dep: InstallManifest.Dep.t) => {
    let versions = findVersions(~name=dep.name, univ);
    if (!seen(dep.name)) {
      markAsSeen(dep.name);
      CudfVersionMap.addPackageVersions(versions, versionMap);
    };
    let matches = pkg =>
      Resolver.versionMatchesDep(
        univ.resolver,
        dep,
        pkg.InstallManifest.name,
        pkg.InstallManifest.version,
      );

    CudfMapping.encodeDepExn(
      ~name=dep.name,
      ~matches,
      {univ, cudfUniv, versionMap},
    );
  };

  let encodeNpmReq = (req: Req.t) => {
    let versions = findVersions(~name=req.name, univ);
    if (!seen(req.name)) {
      markAsSeen(req.name);
      CudfVersionMap.addPackageVersions(versions, versionMap);
    };
    let matches = pkg =>
      Resolver.versionMatchesReq(
        univ.resolver,
        req,
        pkg.InstallManifest.name,
        pkg.InstallManifest.version,
      );

    CudfMapping.encodeDepExn(
      ~name=req.name,
      ~matches,
      {univ, cudfUniv, versionMap},
    );
  };

  let encodeDeps = (deps: Dependencies.t) =>
    switch (deps) {
    | InstallManifest.Dependencies.OpamFormula(deps) =>
      let f = deps => {
        let f = (deps, dep) => deps @ encodeOpamDep(dep);
        List.fold_left(~f, ~init=[], deps);
      };

      List.map(~f, deps);
    | InstallManifest.Dependencies.NpmFormula(reqs) =>
      let reqs = {
        let f = (req: Req.t) => StringMap.mem(req.name, univ.pkgs);
        List.filter(~f, reqs);
      };

      List.map(~f=encodeNpmReq, reqs);
    };

  let encodePkg = (pkgSize, pkg: InstallManifest.t) => {
    let cudfVersion =
      CudfVersionMap.findCudfVersionExn(
        ~name=pkg.name,
        ~version=pkg.version,
        versionMap,
      );

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

  StringMap.iter(
    (name, _) => {
      let versions = findVersions(~name, univ);
      CudfVersionMap.addPackageVersions(versions, versionMap);
      let size = List.length(versions);
      List.iter(~f=encodePkg(size), versions);
    },
    univ.pkgs,
  );

  (cudfUniv, {CudfMapping.univ, cudfUniv, versionMap});
};
