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
    let addVersion = (name, version) => {
      let versions =
        switch (StringMap.find_opt(name, allVersions^)) {
        | Some(versions) => versions
        | None => Version.Set.empty
        };
      allVersions :=
        StringMap.add(name, Version.Set.add(version, versions), allVersions^);
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
            | Dependencies.OpamFormula(_) => ()
            | Dependencies.NpmFormula(reqs) =>
              List.iter(
                ~f=
                  (req: Req.t) =>
                    switch (req.spec) {
                    | VersionSpec.Npm(_) => failwith("npm!")
                    | VersionSpec.NpmDistTag(_) =>
                      /* TODO: use Resolver to get version */
                      failwith("npm-dist-tag!")
                    | VersionSpec.Opam(dep) =>
                      List.iter(
                        ~f=
                          constr =>
                            switch (constr) {
                            | OpamPackageVersion.Constraint.EQ(version)
                            | NEQ(version)
                            | GT(version)
                            | GTE(version)
                            | LT(version)
                            | LTE(version) =>
                              addVersion(req.name, Version.Opam(version))
                            | ANY
                            | NONE => ()
                            },
                        List.flatten(dep),
                      )
                    | VersionSpec.Source(_) =>
                      /* TODO: use Resolver to map to Source.t */
                      /* TODO: map (package_name, Source.t) to 1 version */
                      failwith("source!")
                    },
                reqs,
              )
            };
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
  };

  let encodeOpamDep = (dep: InstallManifest.Dep.t) => {
    let _getCudfVersion = (name, version) =>
      CudfVersionMap.findCudfVersionExn(
        ~name,
        ~version=Version.Opam(version),
        cudfVersionMap,
      );
    switch (dep.req) {
    | InstallManifest.Dep.Npm(req) =>
      switch (req) {
      | SemverVersion.Constraint.EQ(_) => failwith("npm:eq!")
      | NEQ(_) => failwith("npm:neq!")
      | GT(_) => failwith("npm:gt!")
      | GTE(_) => failwith("npm:gte!")
      | LT(_) => failwith("npm:lt!")
      | LTE(_) => failwith("npm:lte!")
      | NONE => failwith("npm:remove NONE!")
      | ANY => [(dep.name, None)]
      }
    | InstallManifest.Dep.NpmDistTag(_) => failwith("npm-dist-tag!")
    | InstallManifest.Dep.Opam(dep) =>
      switch (dep) {
      | OpamPackageVersion.Constraint.EQ(_version) => failwith("eq!")
      | OpamPackageVersion.Constraint.NEQ(_version) => failwith("neq!")
      | OpamPackageVersion.Constraint.GT(_version) => failwith("gt!")
      | OpamPackageVersion.Constraint.GTE(_version) => failwith("gte!")
      | OpamPackageVersion.Constraint.LT(_version) => failwith("lt!")
      | OpamPackageVersion.Constraint.LTE(_version) => failwith("lte!")
      | _ => failwith("other")
      }
    | InstallManifest.Dep.Source(_) => failwith("source!")
    };
  };

  let encodeNpmReq = (req: Req.t) => {
    switch (req.spec) {
    | VersionSpec.Npm(_) => failwith("npm!")
    | VersionSpec.NpmDistTag(_) => failwith("npm-dist-tag!")
    | VersionSpec.Opam(dep) =>
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
      let encConstr = constr =>
        switch (constr) {
        | OpamPackageVersion.Constraint.EQ(version) => v(`Eq, version)
        | NEQ(version) => v(`Neq, version)
        | GT(version) => v(`Gt, version)
        | GTE(version) => v(`Geq, version)
        | LT(version) => v(`Lt, version)
        | LTE(version) => v(`Leq, version)
        | ANY => (req.name, None)
        | NONE => failwith("remove NONE!")
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
    | VersionSpec.Source(_) => failwith("source!")
    };
  };

  // returns CNF:
  // - inner lists are OR-ed
  // - outer lists are AND-ed
  let encodeDeps = (deps: Dependencies.t) =>
    switch (deps) {
    // deps is CNF
    | InstallManifest.Dependencies.OpamFormula(deps) =>
      let f = deps => {
        let f = (deps, dep) => deps @ encodeOpamDep(dep);
        List.fold_left(~f, ~init=[], deps);
      };

      List.map(~f, deps);
    // reqs is CNF
    | InstallManifest.Dependencies.NpmFormula(reqs) =>
      /* Only considering packages which have esy.json / esy config */
      let reqs = {
        let f = (req: Req.t) => StringMap.mem(req.name, univ.pkgs);
        List.filter(~f, reqs);
      };

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
