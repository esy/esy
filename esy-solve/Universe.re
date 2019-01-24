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

  let encodeDepExn = (~name, ~matches, (univ, _cudfUniv, vmap)) => {
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

  /* We add packages in batch by name so this "set of package names" is
   * enough to check if we have handled a pkg already.
   */
  let (seen, markAsSeen) = {
    let names = ref(StringSet.empty);
    let seen = name => StringSet.mem(name, names^);
    let markAsSeen = name => names := StringSet.add(name, names^);
    (seen, markAsSeen);
  };

  let updateVersionMap = pkgs => {
    let f = (cudfVersion, pkg: InstallManifest.t) =>
      CudfVersionMap.update(
        cudfVersionMap,
        pkg.name,
        pkg.version,
        cudfVersion + 1,
      );

    List.iteri(~f, pkgs);
  };

  let encodeOpamDep = (dep: InstallManifest.Dep.t) => {
    let versions = findVersions(~name=dep.name, univ);
    if (!seen(dep.name)) {
      markAsSeen(dep.name);
      updateVersionMap(versions);
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
      (univ, cudfUniv, cudfVersionMap),
    );
  };

  let encodeNpmReq = (req: Req.t) => {
    let versions = findVersions(~name=req.name, univ);
    if (!seen(req.name)) {
      markAsSeen(req.name);
      updateVersionMap(versions);
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
      (univ, cudfUniv, cudfVersionMap),
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
        cudfVersionMap,
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
      updateVersionMap(versions);
      let size = List.length(versions);
      List.iter(~f=encodePkg(size), versions);
    },
    univ.pkgs,
  );

  (cudfUniv, (univ, cudfUniv, cudfVersionMap));
};
