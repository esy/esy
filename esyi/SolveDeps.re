open SolveUtils;

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
      {PackageJson.DependencyRequest.name, req},
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
              ++ PackageJson.DependencyRequest.reqToString(req),
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
          ~cfg,
          ~unique,
          ~previouslyInstalled,
          ~deep,
          name,
          realVersion,
          version,
          pkg,
          state,
          universe,
        ) => {
  CudfVersions.update(
    state.SolveState.cudfVersions,
    name,
    realVersion,
    version,
  );
  Hashtbl.replace(state.cache.manifests, (name, realVersion), pkg);
  deep ?
    List.iter(
      addToUniverse(
        ~cfg,
        ~unique,
        ~previouslyInstalled,
        ~deep,
        state,
        universe,
      ),
      pkg.dependencies.dependencies,
    ) :
    ();
  let package = {
    ...Cudf.default_package,
    package: name,
    version,
    conflicts: unique ? [(name, None)] : [],
    installed:
      switch (previouslyInstalled) {
      | None => false
      | Some(table) => Hashtbl.mem(table, (name, realVersion))
      },
    depends:
      deep ?
        List.map(
          cudfDep(
            name ++ " (at " ++ Solution.Version.toString(realVersion) ++ ")",
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
    (~cfg, ~unique, ~previouslyInstalled, ~deep, state, universe, req) => {
  let versions =
    VersionCache.getAvailableVersions(~cfg, ~cache=state.cache.versions, req)
    |> RunAsync.runExn(~err="error getting versions");
  List.iter(
    versionPlus => {
      let (realVersion, i) =
        switch (versionPlus) {
        | `Github(user, name, ref) => (
            Solution.Version.Github(user, name, ref),
            1,
          )
        | `Opam(v, _, i) => (Solution.Version.Opam(v), i)
        | `Npm(v, _, i) => (Solution.Version.Npm(v), i)
        | `LocalPath(p) => (Solution.Version.LocalPath(p), 2)
        };
      if (!
            Hashtbl.mem(
              state.cudfVersions.lookupIntVersion,
              (req.name, realVersion),
            )) {
        let pkg =
          getCachedManifest(
            state.cache.opamOverrides,
            state.cache.manifests,
            (req.name, versionPlus),
          )
          |> RunAsync.runExn(~err="unable to get manifest");
        addPackage(
          ~cfg,
          ~unique,
          ~previouslyInstalled,
          ~deep,
          req.name,
          realVersion,
          i,
          pkg,
          state,
          universe,
        );
      };
    },
    versions,
  );
};

let rootName = "*root*";

let createUniverse =
    (~cfg, ~unique, ~previouslyInstalled=?, ~deep=true, cache, deps) => {
  let universe = Cudf.empty_universe();
  let state = {SolveState.cache, cudfVersions: CudfVersions.init()};
  /** This is where most of the work happens, file io, network requests, etc. */
  List.iter(
    addToUniverse(
      ~cfg,
      ~unique,
      ~previouslyInstalled,
      ~deep,
      state,
      universe,
    ),
    deps,
  );
  (universe, state.cudfVersions, state.cache.manifests);
};

let solveDeps =
    (
      ~cfg,
      ~unique,
      ~strategy,
      ~previouslyInstalled=?,
      ~deep=true,
      cache,
      deps,
    ) =>
  if (deps == []) {
    [];
  } else {
    let (universe, cudfVersions, manifests) =
      createUniverse(
        ~cfg,
        ~unique,
        ~previouslyInstalled?,
        ~deep,
        cache,
        deps,
      );
    /** Here we invoke the solver! Might also take a while, but probably won't */
    let cudfDeps = List.map(cudfDep(rootName, universe, cudfVersions), deps);
    switch (runSolver(~strategy, rootName, cudfDeps, universe)) {
    | None => failwith("Unable to resolve")
    | Some(packages) =>
      packages
      |> List.filter(p => p.Cudf.package != rootName)
      |> List.map(p => {
           let version = CudfVersions.getRealVersion(cudfVersions, p);
           let pkg = Hashtbl.find(manifests, (p.Cudf.package, version));
           pkg;
         })
    };
  };

module Strategies = {
  let initial = "-notuptodate";
  let greatestOverlap = "-changed,-notuptodate";
};

/* New style! */
let solve = (~cache, ~requested) =>
  solveDeps(
    ~unique=true,
    ~strategy=Strategies.initial,
    ~deep=true,
    cache,
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
  let previouslyInstalled = Hashtbl.create(100);
  current
  |> Hashtbl.iter((name, versions) =>
       versions
       |> List.iter(version =>
            Hashtbl.add(previouslyInstalled, (name, version), true)
          )
     );
  /* current |> List.iter(({Lockfile.SolvedDep.name, version}) => Hashtbl.add(previouslyInstalled, (name, version), 1)); */
  let installed =
    solveDeps(
      ~cfg,
      ~unique=true,
      ~strategy=Strategies.greatestOverlap,
      ~previouslyInstalled,
      ~deep,
      cache,
      requested,
    );
  if (deep) {
    assert(false /* TODO */);
  } else {
    let versionMap = makeVersionMap(installed);
    print_endline("Build deps now");
    requested
    |> List.iter(({PackageJson.DependencyRequest.name, _}) =>
         print_endline(name)
       );
    print_endline("Got");
    installed |> List.iter((pkg: Package.t) => print_endline(pkg.name));
    let touched = Hashtbl.create(100);
    requested
    |> List.iter(({PackageJson.DependencyRequest.name, req}) => {
         let versions = Hashtbl.find(versionMap, name);
         let matching =
           versions |> List.filter(real => SolveUtils.satisfies(real, req));
         switch (matching) {
         | [] =>
           failwith("Didn't actully install a matching dep for " ++ name)
         | [one, ..._] => Hashtbl.replace(touched, (name, one), true)
         };
       });
    installed
    |> List.filter((pkg: Package.t) =>
         Hashtbl.mem(touched, (pkg.name, pkg.version))
       );
  };
};
