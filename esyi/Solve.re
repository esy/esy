module Cache = SolveState.Cache;
module VersionMap = SolveState.VersionMap;
module Source = PackageInfo.Source;
module Version = PackageInfo.Version;
module SourceSpec = PackageInfo.SourceSpec;
module VersionSpec = PackageInfo.VersionSpec;
module Req = PackageInfo.Req;

module Strategies = {
  let initial = "-notuptodate";
  /* let greatestOverlap = "-changed,-notuptodate"; */
};

let runSolver = (~strategy="-notuptodate", ~from, deps, universe) => {
  let root = {
    ...Cudf.default_package,
    package: from.Package.name,
    version: 1,
    depends: deps,
  };
  Cudf.add_package(universe, root);
  let request = {
    ...Cudf.default_request,
    install: [(root.Cudf.package, Some((`Eq, root.Cudf.version)))],
  };
  let preamble = Cudf.default_preamble;
  let solution =
    Mccs.resolve_cudf(
      ~verbose=false,
      ~timeout=5.,
      strategy,
      (preamble, universe, request),
    );
  switch (solution) {
  | None => None
  | Some((_preamble, universe)) =>
    let packages = Cudf.get_packages(~filter=p => p.Cudf.installed, universe);
    Some(packages);
  };
};

let getPackageCached =
    (~state: SolveState.t, name: string, version: PackageInfo.Version.t) => {
  open RunAsync.Syntax;
  let key = (name, version);
  Cache.Packages.compute(
    state.cache.pkgs,
    key,
    _ => {
      let%bind manifest =
        switch (version) {
        | Version.Source(Source.LocalPath(_)) => error("not implemented")
        | Version.Source(Git(_)) => error("not implemented")
        | Version.Source(Github(user, name, ref)) =>
          Package.Github.getManifest(user, name, Some(ref))
        | Version.Source(Source.NoSource) => error("no source")
        | Version.Source(Source.Archive(_)) => error("not implemented")

        | Version.Npm(version) =>
          let%bind manifest =
            NpmRegistry.version(~cfg=state.cfg, name, version);
          return(Package.PackageJson(manifest));

        | Version.Opam(version) =>
          let name = OpamFile.PackageName.ofNpmExn(name);
          switch%bind (
            OpamRegistry.version(state.cache.opamRegistry, ~name, ~version)
          ) {
          | Some(manifest) => return(Package.Opam(manifest))
          | None =>
            error(
              "no such opam package: " ++ OpamFile.PackageName.toString(name),
            )
          };
        };
      let%bind pkg = RunAsync.ofRun(Package.make(~version, manifest));
      return(pkg);
    },
  );
};

let getAvailableVersions = (~state: SolveState.t, req: Req.t) => {
  open RunAsync.Syntax;
  let cache = state.cache;
  let name = Req.name(req);
  let spec = Req.spec(req);

  switch (spec) {
  | VersionSpec.Npm(formula) =>
    let%bind available =
      Cache.NpmPackages.compute(
        cache.availableNpmVersions,
        name,
        name => {
          let%bind versions = NpmRegistry.versions(~cfg=state.cfg, name);
          let () = {
            let cacheManifest = ((version, manifest)) => {
              let version = PackageInfo.Version.Npm(version);
              print_endline(name);
              print_endline(PackageInfo.Version.toString(version));
              print_endline(Req.toString(req));
              let key = (name, version);
              Cache.Packages.ensureComputed(cache.pkgs, key, _ =>
                Lwt.return(
                  Package.make(~version, Package.PackageJson(manifest)),
                )
              );
            };
            List.iter(~f=cacheManifest, versions);
          };
          return(versions);
        },
      );

    available
    |> List.sort(~cmp=((va, _), (vb, _)) =>
         NpmVersion.Version.compare(va, vb)
       )
    |> List.mapi(~f=(i, (v, j)) => (v, j, i))
    |> List.filter(~f=((version, _json, _i)) =>
         NpmVersion.Formula.DNF.matches(formula, ~version)
       )
    |> List.map(~f=((version, _json, i)) => {
         let version = PackageInfo.Version.Npm(version);
         let%bind pkg = getPackageCached(~state, name, version);
         return((pkg, i));
       })
    |> RunAsync.List.joinAll;

  | VersionSpec.Opam(semver) =>
    let%bind available =
      Cache.OpamPackages.compute(
        cache.availableOpamVersions,
        name,
        name => {
          let%bind name = RunAsync.ofRun(OpamFile.PackageName.ofNpm(name));
          let%bind info =
            OpamRegistry.versions(state.cache.opamRegistry, ~name);
          return(info);
        },
      );

    let available =
      available
      |> List.sort(~cmp=((va, _), (vb, _)) =>
           OpamVersion.Version.compare(va, vb)
         )
      |> List.mapi(~f=(i, (v, j)) => (v, j, i));

    let matched =
      available
      |> List.filter(~f=((version, _path, _i)) =>
           OpamVersion.Formula.DNF.matches(semver, ~version)
         );

    let matched =
      if (matched == []) {
        available
        |> List.filter(~f=((version, _path, _i)) =>
             OpamVersion.Formula.DNF.matches(semver, ~version)
           );
      } else {
        matched;
      };

    matched
    |> List.map(~f=((version, _path, i)) => {
         let version = PackageInfo.Version.Opam(version);
         let%bind pkg = getPackageCached(~state, name, version);
         return((pkg, i));
       })
    |> RunAsync.List.joinAll;

  | VersionSpec.Source(SourceSpec.Github(user, name, Some(ref))) =>
    let version = Version.Source(Source.Github(user, name, ref));
    let%bind pkg = getPackageCached(~state, name, version);
    return([(pkg, 1)]);

  | VersionSpec.Source(SourceSpec.Github(_, _, None)) =>
    error("githunb dependencies without commit are not supported")

  | VersionSpec.Source(SourceSpec.Git(_)) =>
    error("git dependencies are not supported")

  | VersionSpec.Source(SourceSpec.NoSource) =>
    error("no source dependencies are not supported")

  | VersionSpec.Source(SourceSpec.Archive(_)) =>
    error("archive dependencies are not supported")

  | VersionSpec.Source(SourceSpec.LocalPath(p)) =>
    let version = Version.Source(Source.LocalPath(p));
    let%bind pkg = getPackageCached(~state, name, version);
    return([(pkg, 2)]);
  };
};

module Seen = {
  type t = Hashtbl.t((string, Version.t), bool);

  let make = () : t => Hashtbl.create(100);

  let add = (seen, pkg: Package.t) =>
    Hashtbl.replace(seen, (pkg.name, pkg.version), true);

  let seen = (seen, pkg: Package.t) =>
    switch (Hashtbl.find_opt(seen, (pkg.name, pkg.version))) {
    | Some(v) => v
    | None => false
    };
};

let initState =
    (~cfg, ~cache=?, ~resolutions, ~root: Package.t, deps: list(Req.t)) => {
  open RunAsync.Syntax;

  let seen = Seen.make();
  let%bind state = SolveState.make(~cache?, ~cfg, ());

  let applyResolutions = (~resolutions, req) =>
    switch (PackageInfo.Resolutions.apply(resolutions, req)) {
    | Some(req) =>
      Printf.printf("[INFO] Using resolution %s\n", Req.toString(req));
      req;
    | None => req
    };

  let rec addToUniverse = req => {
    let versions =
      getAvailableVersions(~state, req)
      |> RunAsync.withContext("processing request: " ++ Req.toString(req))
      |> RunAsync.runExn(~err="error getting versions");

    let addVersion = ((pkg: Package.t, cudfVersion)) =>
      if (! Seen.seen(seen, pkg)) {
        Seen.add(seen, pkg);

        /** Recurse into dependencies first and then add the package itself. */
        let dependencies =
          List.map(
            ~f=applyResolutions(~resolutions),
            pkg.dependencies.dependencies,
          );
        List.iter(~f=addToUniverse, dependencies);
        SolveState.addPackage(~state, ~cudfVersion, ~dependencies, pkg);
      };

    List.iter(~f=addVersion, versions);
  };

  let request =
    List.map(
      ~f=
        req => {
          let req = applyResolutions(~resolutions, req);
          addToUniverse(req);
          SolveState.cudfDep(~state, ~from=root, req);
        },
      deps,
    );

  return((state, request));
};

let solveDeps = (~state: SolveState.t, ~from: Package.t, request) =>
  RunAsync.Syntax.(
    if (request == []) {
      return([]);
    } else {
      /** Here we invoke the solver! Might also take a while, but probably won't */
      (
        switch (
          runSolver(
            ~strategy=Strategies.initial,
            ~from,
            request,
            state.universe,
          )
        ) {
        | None => error("Unable to resolve")
        | Some(packages) =>
          packages
          |> List.filter(~f=p => p.Cudf.package != from.Package.name)
          |> List.map(~f=p => {
               let version =
                 VersionMap.findVersionExn(
                   state.versionMap,
                   ~name=p.Cudf.package,
                   ~cudfVersion=p.Cudf.version,
                 );
               switch (
                 Cache.Packages.get(
                   state.cache.pkgs,
                   (p.Cudf.package, version),
                 )
               ) {
               | Some(value) => value
               | None => error("missing package: " ++ p.Cudf.package)
               };
             })
          |> RunAsync.List.joinAll
        }
      );
    }
  );

let solve = (~cfg, ~resolutions, pkg: Package.t) =>
  RunAsync.Syntax.(
    {
      /** Cache can be shared between the dependencied */
      let%bind cache = SolveState.Cache.make(~cfg, ());
      let%bind (state, request) =
        initState(
          ~cfg,
          ~cache,
          ~resolutions,
          ~root=pkg,
          pkg.dependencies.dependencies,
        );

      let%bind deps = solveDeps(~state, ~from=pkg, request);

      let solution = {
        let makePkg = (pkg: Package.t) => {
          Solution.name: pkg.name,
          version: pkg.version,
          source: pkg.source,
          opam: pkg.opam,
        };

        let pkg = makePkg(pkg);
        let bag = List.map(~f=(pkg: Package.t) => makePkg(pkg), deps);
        {Solution.pkg, bag};
      };

      return(solution);
    }
  );
