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

/* let encodeNpmFormula = (~state, formula) => { */
/*   module F = NpmVersion.Formula; */
/*   module C = NpmVersion.Formula.Constraint; */
/*   let versionMap = state.SolveState.versionMap; */
/*   let encodeConstraint = (~state, constr: NpmVersion.Formula.Constraint.t) => */
/*     switch (constr) { */
/*     | C.EQ(_) => (??) */
/*     | C.GT(_) => (??) */
/*     | C.GTE(_) => (??) */
/*     | C.LT(_) => (??) */
/*     | C.LTE(_) => (??) */
/*     | C.NONE => None */
/*     | C.ANY => None */
/*     }; */
/*   let F.AND(formula) = NpmVersion.Formula.ofDnfToCnf(formula); */
/*   List.map( */
/*     (F.OR(disj)) => List.map(encodeConstraint(~state), disj), */
/*     formula, */
/*   ); */
/* }; */

/* let encodeOpamFormula = (~state, formula) => { */
/*   module F = OpamVersion.Formula; */
/*   module C = OpamVersion.Formula.Constraint; */
/*   let encodeConstraint = (~state, constr: OpamVersion.Formula.Constraint.t) => { */
/*     (); */
/*     (); */
/*   }; */
/*   let F.AND(formula) = OpamVersion.Formula.ofDnfToCnf(formula); */
/*   List.map( */
/*     (F.OR(disj)) => List.map(encodeConstraint(~state), disj), */
/*     formula, */
/*   ); */
/* }; */

/* let encodeDep = (~state, req: Req.t) => { */
/*   let name = Req.name(req); */
/*   let spec = Req.spec(req); */
/*   switch (spec) { */
/*   | VersionSpec.Npm(formula) => Some(encodeNpmFormula(~state, formula)) */
/*   | VersionSpec.Opam(formula) => Some(encodeOpamFormula(~state, formula)) */
/*   | VersionSpec.Source(_) => */
/*     /1* TODO: We should resolve to the source here *1/ */
/*     None */
/*   }; */
/* }; */

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
