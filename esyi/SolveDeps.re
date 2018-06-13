module Cache = SolveState.Cache;
module VersionMap = SolveState.VersionMap;
module Source = PackageInfo.Source;
module Version = PackageInfo.Version;
module SourceSpec = PackageInfo.SourceSpec;
module VersionSpec = PackageInfo.VersionSpec;
module Req = PackageInfo.Req;

let runSolver = (~strategy="-notuptodate", rootName, deps, universe) => {
  let root = {
    ...Cudf.default_package,
    package: rootName,
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

  let make = () => Hashtbl.create(100);

  let add = (seen, pkg: Package.t) =>
    Hashtbl.replace(seen, (pkg.name, pkg.version), true);

  let seen = (seen, pkg: Package.t) =>
    switch (Hashtbl.find_opt(seen, (pkg.name, pkg.version))) {
    | Some(v) => v
    | None => false
    };
};

let rec addToUniverse =
        (~state: SolveState.t, ~seen, ~previouslyInstalled=?, req) => {
  let versions =
    getAvailableVersions(~state, req)
    |> RunAsync.withContext("processing request: " ++ Req.toString(req))
    |> RunAsync.runExn(~err="error getting versions");
  List.iter(
    ~f=
      ((pkg: Package.t, cudfVersion)) =>
        if (! Seen.seen(seen, pkg)) {
          Seen.add(seen, pkg);

          List.iter(
            ~f=addToUniverse(~state, ~previouslyInstalled?, ~seen),
            pkg.dependencies.dependencies,
          );

          SolveState.addPackage(
            ~state,
            ~previouslyInstalled,
            ~cudfVersion,
            pkg,
          );
        },
    versions,
  );
};

let rootName = "*root*";

let initState = (~cfg, ~previouslyInstalled=?, ~cache=?, deps) =>
  RunAsync.Syntax.(
    {
      let%bind state = SolveState.make(~cache?, ~cfg, ());
      /** This is where most of the work happens, file io, network requests, etc. */
      let seen = Seen.make();
      List.iter(
        ~f=addToUniverse(~state, ~seen, ~previouslyInstalled?),
        deps,
      );
      return((state.universe, state.versionMap, state.cache.pkgs));
    }
  );

let solveDeps =
    (~cfg, ~cache, ~strategy, ~previouslyInstalled=?, deps) =>
  RunAsync.Syntax.(
    if (deps == []) {
      return([]);
    } else {
      let%bind (universe, versionMap, manifests) =
        initState(~cfg, ~previouslyInstalled?, ~cache, deps);
      /** Here we invoke the solver! Might also take a while, but probably won't */
      let cudfDeps =
        List.map(
          ~f=SolveState.cudfDep(rootName, universe, cudfVersions),
          deps,
        );
      switch (runSolver(~strategy, rootName, cudfDeps, universe)) {
      | None => error("Unable to resolve")
      | Some(packages) =>
        packages
        |> List.filter(~f=p => p.Cudf.package != rootName)
        |> List.map(~f=p => {
             let version =
               VersionMap.findVersionExn(
                 cudfVersions,
                 ~name=p.Cudf.package,
                 ~cudfVersion=p.Cudf.version,
               );
             switch (
               Cache.Packages.get(manifests, (p.Cudf.package, version))
             ) {
             | Some(value) => value
             | None => error("missing package: " ++ p.Cudf.package)
             };
           })
        |> RunAsync.List.joinAll
      };
    }
  );

module Strategies = {
  let initial = "-notuptodate";
  let greatestOverlap = "-changed,-notuptodate";
};

let solve = (~cfg, ~cache, ~requested) =>
  solveDeps(
    ~cfg,
    ~cache,
    ~strategy=Strategies.initial,
    requested,
  );
