open SolveUtils;
module Cache = SolveState.Cache;

/**
 *
 * Order of operations:
 * - solve for real deps of the main module
 * - [list of solved deps], [list of build deps requests for MAIN]
 * - can look in the manifest cache for build deps of the solved deps
 *
 * - now I want to dedup where possible, so I'm installing the minimum amount of build deps
 * - now I have a list of list((name, list(realVersion))) that is the versions of the build deps to install
 * - for each of those, do `solveDeps(cache, depsOfThatOneRealVersion)`
 *   - build deps aren't allowed to depend on each other I don't think
 * - that will result in new buildDeps needed
 * - churn until we're done
 *
 * - when making the lockfile, for each build dep that a thing wants, find one that we've chosen, whichever is most recent probably
 *
 */
let cudfDep =
    (
      owner,
      universe,
      cudfVersions,
      {PackageInfo.DependencyRequest.name, req},
    ) => {
  let available = Cudf.lookup_packages(universe, name);
  let matching =
    available |> List.filter(CudfVersions.matchesSource(req, cudfVersions));
  let final =
    (
      if (matching == []) {
        let hack =
          switch (req) {
          | Opam(opamVersionRange) =>
            available
            |> List.filter(
                 CudfVersions.matchesSource(
                   Opam(opamVersionRange),
                   cudfVersions,
                 ),
               )
          | _ => []
          };
        switch (hack) {
        | [] =>
          /* We know there are packages that want versions of ocaml we don't support, it's ok */
          if (name == "ocaml") {
            [];
          } else {
            print_endline(
              "\240\159\155\145 \240\159\155\145 \240\159\155\145  Requirement unsatisfiable "
              ++ owner
              ++ " wants "
              ++ name
              ++ " at version "
              ++ PackageInfo.DependencyRequest.reqToString(req),
            );
            available
            |> List.iter(package =>
                 print_endline(
                   "  - "
                   ++ Solution.Version.toString(
                        CudfVersions.getRealVersion(cudfVersions, package),
                      ),
                 )
               );
            [];
          }
        | matching => matching
        };
      } else {
        matching;
      }
    )
    |> List.map(package =>
         (package.Cudf.package, Some((`Eq, package.Cudf.version)))
       );
  /** If no matching packages, make a requirement for a package that doesn't exist. */
  final
  == [] ?
    [("**not-a-packge%%%", Some((`Eq, 10000000000)))] : final;
};

let getPackageCached =
    (~state: SolveState.t, name: string, version: Solution.Version.t) => {
  open RunAsync.Syntax;
  let key = (name, version);
  Cache.Packages.compute(
    state.cache.pkgs,
    key,
    _ => {
      let%bind manifest =
        switch (version) {
        | Solution.Version.LocalPath(_) => error("not implemented")
        | Solution.Version.Git(_) => error("not implemented")
        | Solution.Version.Github(user, name, ref) =>
          Package.Github.getManifest(user, name, ref)

        | Solution.Version.Npm(version) =>
          let%bind manifest =
            NpmRegistry.version(~cfg=state.cfg, name, version);
          return(Package.PackageJson(manifest));

        | Solution.Version.Opam(version) =>
          switch%bind (
            OpamRegistry.version(
              ~cfg=state.cfg,
              ~opamOverrides=state.cache.opamOverrides,
              name,
              version,
            )
          ) {
          | Some(manifest) => return(Package.Opam(manifest))
          | None => error("no such opam package: " ++ name)
          }
        };
      let%bind pkg = RunAsync.ofRun(Package.make(~version, manifest));
      return(pkg);
    },
  );
};

let getAvailableVersions =
    (~state: SolveState.t, req: PackageInfo.DependencyRequest.t) => {
  open RunAsync.Syntax;
  let cache = state.cache;

  switch (req.req) {
  | PackageInfo.DependencyRequest.Github(user, name, ref) =>
    let version = Solution.Version.Github(user, name, ref);
    let%bind pkg = getPackageCached(~state, req.name, version);
    return([(pkg, 1)]);

  | Npm(formula) =>
    let%bind available =
      Cache.NpmPackages.compute(
        cache.availableNpmVersions,
        req.name,
        name => {
          let%bind versions = NpmRegistry.versions(~cfg=state.cfg, name);
          let () = {
            let cacheManifest = ((version, manifest)) => {
              let version = Solution.Version.Npm(version);
              let key = (name, version);
              Cache.Packages.ensureComputed(cache.pkgs, key, _ =>
                Lwt.return(
                  Package.make(~version, Package.PackageJson(manifest)),
                )
              );
            };
            List.iter(cacheManifest, versions);
          };
          return(versions);
        },
      );

    available
    |> List.sort(((va, _), (vb, _)) => NpmVersion.Version.compare(va, vb))
    |> List.mapi((i, (v, j)) => (v, j, i))
    |> List.filter(((version, _json, _i)) =>
         NpmVersion.Formula.matches(formula, version)
       )
    |> List.map(((version, _json, i)) => {
         let version = Solution.Version.Npm(version);
         let%bind pkg = getPackageCached(~state, req.name, version);
         return((pkg, i));
       })
    |> RunAsync.List.joinAll;

  | Opam(semver) =>
    let%bind available =
      Cache.OpamPackages.compute(
        cache.availableOpamVersions,
        req.name,
        _ => {
          let%bind info = OpamRegistry.versions(~cfg=state.cfg, req.name);
          return(info);
        },
      );

    let available =
      available
      |> List.sort(((va, _), (vb, _)) =>
           OpamVersion.Version.compare(va, vb)
         )
      |> List.mapi((i, (v, j)) => (v, j, i));

    let matched =
      available
      |> List.filter(((version, _path, _i)) =>
           OpamVersion.Formula.matches(semver, version)
         );

    let matched =
      if (matched == []) {
        available
        |> List.filter(((version, _path, _i)) =>
             OpamVersion.Formula.matches(semver, version)
           );
      } else {
        matched;
      };

    matched
    |> List.map(((version, _path, i)) => {
         let version = Solution.Version.Opam(version);
         let%bind pkg = getPackageCached(~state, req.name, version);
         return((pkg, i));
       })
    |> RunAsync.List.joinAll;
  | Git(_) => error("git dependencies are not supported")
  | LocalPath(p) =>
    let version = Solution.Version.LocalPath(p);
    let%bind pkg = getPackageCached(~state, req.name, version);
    return([(pkg, 2)]);
  };
};

/* TODO need to figure out how to specify what deps we're interested in.
 *
 * Maybe a fn: Types.depsByKind => List(Types.dep)
 *
 * orr maybe we don't? Maybe
 *
 * do we just care about runtime deps?
 * Do we care about runtime deps being the same as build deps?
 * kindof, a little. But how do we enforce that?
 * How do we do that.
 * Do we care about runtime deps of our build deps being the same as runtime deps of our other build deps?
 *
 * whaaat rabbit hole is this even.
 *
 * What are the initial constraints?
 *
 * For runtime:
 * - so easy, just bring it all in, require uniqueness, ignoring dev deps at every step
 * - if there's already a lockfile, then mark those ones as already installed and do "-changed,-notuptodate"
 *
 * For [target]:
 * - do essentially the same thing -- include current installs, try to have minimal changes
 *
 * For build:
 * - all of those runtime deps we got, figure out what build deps they want
 * - loop until our "pending build deps" list is done
 *   - filter out all build dep reqs that are already satisfied by packages we've already downloaded
 *   - run a unique query that doesn't do any transitives - just deduping build requirements
 *   - if that fails, fallback to a non-unique query
 *   - now that we know which build deps we want to install, loop through each one
 *     - for its runtime deps, do a unique with -changed, including all currently installed packages
 *     - collect all transitive build deps, add them to the list of build deps to get
 *
 *
 *
 * For npm:
 * - this is the last step -- npm deps can't loop back to runtime or build deps
 * - it's easy, because they're all runtime deps. We're solid, just run with it.
 * - first do a pass with uniqueness
 * - if it doesn't work, do a pass without uniqueness, and then post-process to remove duplicates where possible
 */
/*
 * type fullPackage =
 * - source:
 * - version: (yeah this isn't as relevant)
 * - runtime:
 *   - [name]:
 *     - (name, versionRange, realVersion)
 * - build:
 *   - (name, versionRange, realVersion)
 * - npm:
 *   - [name]:
 *     - requestedVersion:
 *     - resolvedVersion:
 *     - dependencies:
 *       - [name]: // only listed if this dep isn't satisfied at a higher level
 *         (recurse)
 *
 * Currently we have:
 * - targets:
 *   [target=default,ios,etc.]:
 *    - package:
 *      {fullPackage}
 *    - runtimeBag:
 *      - [name]:
 *        {fullPackage}
 *
 * - buildDependencies:
 *   [name:version]
 *    - package:
 *      {fullPackage}
 *    - runtimeBag:
 *      - [name]:
 *        {fullPackage}
 *
 */
let rec addPackage =
        (
          ~state,
          ~previouslyInstalled,
          ~deep,
          pkg: Package.t,
          version,
          universe,
        ) => {
  CudfVersions.update(
    state.SolveState.cudfVersions,
    pkg.name,
    pkg.version,
    version,
  );
  Cache.Packages.put(
    state.cache.pkgs,
    (pkg.name, pkg.version),
    RunAsync.return(pkg),
  );
  deep ?
    List.iter(
      addToUniverse(~state, ~previouslyInstalled, ~deep, universe),
      pkg.dependencies.dependencies,
    ) :
    ();
  let package = {
    ...Cudf.default_package,
    package: pkg.name,
    version,
    conflicts: [(pkg.name, None)],
    installed:
      switch (previouslyInstalled) {
      | None => false
      | Some(table) => Hashtbl.mem(table, (pkg.name, pkg.version))
      },
    depends:
      deep ?
        List.map(
          cudfDep(
            pkg.name
            ++ " (at "
            ++ Solution.Version.toString(pkg.version)
            ++ ")",
            universe,
            state.cudfVersions,
          ),
          pkg.dependencies.dependencies,
        ) :
        [],
  };
  Cudf.add_package(universe, package);
}
and addToUniverse =
    (~state: SolveState.t, ~previouslyInstalled, ~deep, universe, req) => {
  let versions =
    getAvailableVersions(~state, req)
    |> RunAsync.runExn(~err="error getting versions");
  List.iter(
    ((pkg: Package.t, cudfVersion)) =>
      if (!
            Hashtbl.mem(
              state.cudfVersions.lookupIntVersion,
              (pkg.name, pkg.version),
            )) {
        addPackage(
          ~state,
          ~previouslyInstalled,
          ~deep,
          pkg,
          cudfVersion,
          universe,
        );
      },
    versions,
  );
};

let rootName = "*root*";

let createUniverse = (~cfg, ~cache, ~previouslyInstalled=?, ~deep=true, deps) => {
  open RunAsync.Syntax;
  let universe = Cudf.empty_universe();
  let%bind state = SolveState.make(~cache, ~cfg, ());
  /** This is where most of the work happens, file io, network requests, etc. */
  List.iter(
    addToUniverse(~state, ~previouslyInstalled, ~deep, universe),
    deps,
  );
  return((universe, state.cudfVersions, state.cache.pkgs));
};

let solveDeps =
    (~cfg, ~cache, ~strategy, ~previouslyInstalled=?, ~deep=true, deps) =>
  RunAsync.Syntax.(
    if (deps == []) {
      return([]);
    } else {
      let%bind (universe, cudfVersions, manifests) =
        createUniverse(~cfg, ~cache, ~previouslyInstalled?, ~deep, deps);
      /** Here we invoke the solver! Might also take a while, but probably won't */
      let cudfDeps =
        List.map(cudfDep(rootName, universe, cudfVersions), deps);
      switch (runSolver(~strategy, rootName, cudfDeps, universe)) {
      | None => error("Unable to resolve")
      | Some(packages) =>
        packages
        |> List.filter(p => p.Cudf.package != rootName)
        |> List.map(p => {
             let version = CudfVersions.getRealVersion(cudfVersions, p);
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
    ~deep=true,
    requested,
  );

let makeVersionMap = installed => {
  let map = Hashtbl.create(100);
  installed
  |> List.iter((pkg: Package.t) => {
       let current =
         Hashtbl.mem(map, pkg.name) ? Hashtbl.find(map, pkg.name) : [];
       Hashtbl.replace(map, pkg.name, [pkg.version, ...current]);
     });
  /* TODO sort the entries... so we get the latest when possible */
  map;
};

/**
 * - we allow multiple versions
 * - we provide a list of modules that are already installed
 * - if we want, we only go one level deep
 */
let solveLoose = (~cfg, ~cache, ~requested, ~current, ~deep) => {
  open RunAsync.Syntax;
  let previouslyInstalled = Hashtbl.create(100);
  current
  |> Hashtbl.iter((name, versions) =>
       versions
       |> List.iter(version =>
            Hashtbl.add(previouslyInstalled, (name, version), true)
          )
     );
  /* current |> List.iter(({Lockfile.SolvedDep.name, version}) => Hashtbl.add(previouslyInstalled, (name, version), 1)); */
  let%bind installed =
    solveDeps(
      ~cfg,
      ~cache,
      ~strategy=Strategies.greatestOverlap,
      ~previouslyInstalled,
      ~deep,
      requested,
    );
  if (deep) {
    assert(false /* TODO */);
  } else {
    let versionMap = makeVersionMap(installed);
    print_endline("Build deps now");
    requested
    |> List.iter(({PackageInfo.DependencyRequest.name, _}) =>
         print_endline(name)
       );
    print_endline("Got");
    installed |> List.iter((pkg: Package.t) => print_endline(pkg.name));
    let touched = Hashtbl.create(100);
    requested
    |> List.iter(({PackageInfo.DependencyRequest.name, req}) => {
         let versions = Hashtbl.find(versionMap, name);
         let matching =
           versions |> List.filter(real => SolveUtils.satisfies(real, req));
         switch (matching) {
         | [] =>
           failwith("Didn't actully install a matching dep for " ++ name)
         | [one, ..._] => Hashtbl.replace(touched, (name, one), true)
         };
       });
    return(
      installed
      |> List.filter((pkg: Package.t) =>
           Hashtbl.mem(touched, (pkg.name, pkg.version))
         ),
    );
  };
};
