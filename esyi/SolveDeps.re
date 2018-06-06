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

let toRealVersion = versionPlus =>
  switch (versionPlus) {
  | `Github(user, repo, ref) => Solution.Version.Github(user, repo, ref)
  | `Npm(x, _, _) => Solution.Version.Npm(x)
  | `Opam(x, _, _) => Solution.Version.Opam(x)
  | `LocalPath(p) => Solution.Version.LocalPath(p)
  };

let getPackageCached = (~state: SolveState.t, (name, versionPlus)) => {
  open RunAsync.Syntax;
  let realVersion = toRealVersion(versionPlus);
  switch (Hashtbl.find(state.cache.pkgs, (name, realVersion))) {
  | exception Not_found =>
    let promise = {
      let%bind manifest =
        switch (versionPlus) {
        | `Github(user, repo, ref) =>
          Package.Github.getManifest(user, repo, ref)
        /* Registry.getGithubManifest(url) */
        | `Npm(_version, json, _) => return(Package.PackageJson(json))
        | `LocalPath(_p) =>
          error("do not know how to get manifest from LocalPath")
        | `Opam(_version, path, _) =>
          let%bind manifest =
            OpamRegistry.getManifest(state.cache.opamOverrides, path);
          return(Package.Opam(manifest));
        };
      let%bind pkg =
        RunAsync.ofRun(Package.make(~version=realVersion, manifest));
      return(pkg);
    };
    Hashtbl.replace(state.cache.pkgs, (name, realVersion), promise);
    promise;
  | promise => promise
  };
};

let getAvailableVersions = (~state: SolveState.t, req) => {
  open RunAsync.Syntax;
  let cache = state.cache;
  switch (req.PackageInfo.DependencyRequest.req) {
  | PackageInfo.DependencyRequest.Github(user, repo, ref) =>
    return([`Github((user, repo, ref))])
  | Npm(semver) =>
    let%bind () =
      if (! Hashtbl.mem(cache.availableNpmVersions, req.name)) {
        let%bind versions = NpmRegistry.resolve(~cfg=state.cfg, req.name);
        Hashtbl.replace(cache.availableNpmVersions, req.name, versions);
        return();
      } else {
        return();
      };
    let available = Hashtbl.find(cache.availableNpmVersions, req.name);
    return(
      available
      |> List.sort(((va, _), (vb, _)) =>
           NpmVersion.Version.compare(va, vb)
         )
      |> List.mapi((i, (v, j)) => (v, j, i))
      |> List.filter(((version, _json, _i)) =>
           NpmVersion.Formula.matches(semver, version)
         )
      |> List.map(((version, json, i)) => `Npm((version, json, i))),
    );
  | Opam(semver) =>
    let%bind () =
      if (! Hashtbl.mem(cache.availableOpamVersions, req.name)) {
        let info =
          OpamRegistry.getFromOpamRegistry(~cfg=state.cfg, req.name)
          |> RunAsync.runExn(~err="unable to get info on opam package");
        Hashtbl.replace(cache.availableOpamVersions, req.name, info);
        return();
      } else {
        return();
      };
    let available =
      Hashtbl.find(cache.availableOpamVersions, req.name)
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
    return(
      matched |> List.map(((version, path, i)) => `Opam((version, path, i))),
    );
  | Git(_) => error("git dependencies are not supported")
  | LocalPath(p) => return([`LocalPath(p)])
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
          ~unique,
          ~previouslyInstalled,
          ~deep,
          name,
          realVersion,
          version,
          pkg: Package.t,
          universe,
        ) => {
  CudfVersions.update(
    state.SolveState.cudfVersions,
    name,
    realVersion,
    version,
  );
  Hashtbl.replace(
    state.cache.pkgs,
    (name, realVersion),
    RunAsync.return(pkg),
  );
  deep ?
    List.iter(
      addToUniverse(~state, ~unique, ~previouslyInstalled, ~deep, universe),
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
    (
      ~state: SolveState.t,
      ~unique,
      ~previouslyInstalled,
      ~deep,
      universe,
      req,
    ) => {
  let versions =
    getAvailableVersions(~state, req)
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
          getPackageCached(~state, (req.name, versionPlus))
          |> RunAsync.runExn(~err="unable to get manifest");
        addPackage(
          ~state,
          ~unique,
          ~previouslyInstalled,
          ~deep,
          req.name,
          realVersion,
          i,
          pkg,
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
  open RunAsync.Syntax;
  let universe = Cudf.empty_universe();
  let%bind state = SolveState.make(~cache, ~cfg, ());
  /** This is where most of the work happens, file io, network requests, etc. */
  List.iter(
    addToUniverse(~state, ~unique, ~previouslyInstalled, ~deep, universe),
    deps,
  );
  return((universe, state.cudfVersions, state.cache.pkgs));
};

let solveDeps =
    (
      ~cfg,
      ~cache,
      ~unique,
      ~strategy,
      ~previouslyInstalled=?,
      ~deep=true,
      deps,
    ) =>
  RunAsync.Syntax.(
    if (deps == []) {
      return([]);
    } else {
      let%bind (universe, cudfVersions, manifests) =
        createUniverse(
          ~cfg,
          ~unique,
          ~previouslyInstalled?,
          ~deep,
          cache,
          deps,
        );
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
             let pkg = Hashtbl.find(manifests, (p.Cudf.package, version));
             pkg;
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
    ~unique=true,
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
      ~unique=true,
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
