let unsatisfied = (map, {PackageJson.DependencyRequest.name, req}) =>
  switch (Hashtbl.find(map, name)) {
  | exception Not_found => true
  | versions => ! List.exists(v => SolveUtils.satisfies(v, req), versions)
  };

let justDepsn = ((_, _, _, deps)) => deps;

let settleBuildDeps = (~cfg, cache, solvedDeps, requestedBuildDeps) => {
  let allTransitiveBuildDeps =
    solvedDeps
    |> List.map(justDepsn)
    |> List.map(deps => deps.PackageJson.DependenciesInfo.buildDependencies)
    |> List.concat;
  /* let allTransitiveBuildDeps = allNeededBuildDeps @ (
       solvedTargets |> List.map(((_, deps)) => getBuildDeps(deps)) |> List.concat |> List.concat
     ); */
  let buildDepsToInstall = allTransitiveBuildDeps @ requestedBuildDeps;
  let nameToVersions = Hashtbl.create(100);
  let versionMap = Hashtbl.create(100);
  let rec loop = (buildDeps: PackageJson.Dependencies.t) => {
    let toAdd = buildDeps |> List.filter(unsatisfied(nameToVersions));
    if (toAdd != []) {
      let solved =
        SolveDeps.solveLoose(
          ~cfg,
          ~cache,
          ~requested=toAdd,
          ~current=nameToVersions,
          ~deep=false,
        );
      solved
      |> List.map(((name, version, manifest, deps)) =>
           if (! Hashtbl.mem(versionMap, (name, version))) {
             Hashtbl.replace(
               nameToVersions,
               name,
               [
                 version,
                 ...Hashtbl.mem(nameToVersions, name) ?
                      Hashtbl.find(nameToVersions, name) : [],
               ],
             );
             let solvedDeps =
               SolveDeps.solve(
                 ~cfg,
                 ~cache,
                 ~requested=deps.PackageJson.DependenciesInfo.dependencies,
               );
             Hashtbl.replace(
               versionMap,
               (name, version),
               (manifest, deps, solvedDeps),
             );
             let childBuilds =
               solvedDeps
               |> List.map(justDepsn)
               |> List.map(deps =>
                    deps.PackageJson.DependenciesInfo.buildDependencies
                  )
               |> List.concat;
             childBuilds @ deps.PackageJson.DependenciesInfo.buildDependencies;
           } else {
             [];
           }
         )
      |> List.concat
      |> (buildDeps => loop(buildDeps));
    };
  };
  loop(buildDepsToInstall);
  (versionMap, nameToVersions);
};

let solve = (~cfg, manifest) =>
  RunAsync.Syntax.(
    {
      let%bind () = SolveUtils.checkRepositories(cfg);
      let cache = SolveDeps.initCache(cfg);
      let depsByKind = Manifest.dependencies(manifest);
      let solvedDeps =
        SolveDeps.solve(~cfg, ~cache, ~requested=depsByKind.dependencies);
      let (buildVersionMap, _buildToVersions) =
        settleBuildDeps(
          ~cfg,
          cache,
          solvedDeps,
          depsByKind.buildDependencies,
        );

      let makePkg = (manifest, name, version) => {
        let%bind source =
          RunAsync.ofRun(Manifest.source(manifest, name, version));
        let%bind source = SolveUtils.lockDownSource(source);
        return({Solution.name, version, source});
      };

      let makeRootPkg = (pkg, deps) => {
        let%bind bag =
          deps
          |> List.map(((name, version, manifest, _deps)) =>
               makePkg(manifest, name, version)
             )
          |> RunAsync.List.joinAll;
        return({Solution.pkg, bag});
      };

      let%bind root = {
        let%bind pkg =
          makePkg(
            manifest,
            "*root",
            Solution.Version.LocalPath(Path.v("./")),
          );
        makeRootPkg(pkg, solvedDeps);
      };

      let%bind buildDependencies =
        Hashtbl.fold(
          ((name, version), (manifest, _deps, solvedDeps), result) => [
            (manifest, name, version, solvedDeps),
            ...result,
          ],
          buildVersionMap,
          [],
        )
        |> List.map(((manifest, name, version, deps)) => {
             let%bind pkg = makePkg(manifest, name, version);
             makeRootPkg(pkg, deps);
           })
        |> RunAsync.List.joinAll;

      let env = {Solution.root, buildDependencies};
      return(env);
    }
  );
