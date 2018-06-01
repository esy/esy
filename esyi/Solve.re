let unsatisfied = (map, {PackageJson.DependencyRequest.name, req}) =>
  switch (Hashtbl.find(map, name)) {
  | exception Not_found => true
  | versions => ! List.exists(v => SolveUtils.satisfies(v, req), versions)
  };

let findSatisfyingInMap = (map, name, range) =>
  List.find(v => SolveUtils.satisfies(v, range), Hashtbl.find(map, name));

let justDepsn = ((_, _, _, deps)) => deps;

let makeFullPackage =
    (name, version, manifest, deps, solvedDeps, buildToVersions) => {
  let nameToVersion = Hashtbl.create(100);
  solvedDeps
  |> List.iter(((name, version, _, _)) =>
       Hashtbl.replace(nameToVersion, name, version)
     );
  Env.{
    package: {
      name,
      version,
      source: Manifest.getSource(manifest, name, version),
      requested: deps,
      runtime:
        deps.PackageJson.DependenciesInfo.dependencies
        |> List.map(({PackageJson.DependencyRequest.name, req}) =>
             (name, req, Hashtbl.find(nameToVersion, name))
           ),
      build:
        deps.PackageJson.DependenciesInfo.buildDependencies
        |> List.map(({PackageJson.DependencyRequest.name, req}) =>
             (name, req, findSatisfyingInMap(buildToVersions, name, req))
           ),
    },
    runtimeBag:
      solvedDeps
      |> List.map(((name, version, manifest, deps)) =>
           {
             name,
             version,
             source: Manifest.getSource(manifest, name, version),
             requested: deps,
             runtime:
               deps.PackageJson.DependenciesInfo.dependencies
               |> List.map(({PackageJson.DependencyRequest.name, req}) =>
                    (name, req, Hashtbl.find(nameToVersion, name))
                  ),
             build:
               deps.PackageJson.DependenciesInfo.buildDependencies
               |> List.map(({PackageJson.DependencyRequest.name, req}) =>
                    (
                      name,
                      req,
                      findSatisfyingInMap(buildToVersions, name, req),
                    )
                  ),
           }
         ),
  };
};

let settleBuildDeps = (~config, cache, solvedDeps, requestedBuildDeps) => {
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
          ~config,
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
                 ~config,
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

let solve = (config, manifest) =>
  RunAsync.Syntax.(
    {
      let%bind () = SolveUtils.checkRepositories(config);
      let cache = SolveDeps.initCache(config);
      let depsByKind = Manifest.getDeps(manifest);
      let solvedDeps =
        SolveDeps.solve(~config, ~cache, ~requested=depsByKind.dependencies);
      let (buildVersionMap, buildToVersions) =
        settleBuildDeps(
          ~config,
          cache,
          solvedDeps,
          depsByKind.buildDependencies,
        );

      let lockdownFullPackage = full => {
        let%bind source = SolveUtils.lockDownSource(full.Env.source);
        return({
          Solution.name: full.Env.name,
          version: full.Env.version,
          source,
        });
      };

      let lockdownRootPackage = root => {
        let%bind pkg = lockdownFullPackage(root.Env.package);
        let%bind bag =
          root.Env.runtimeBag
          |> List.map(lockdownFullPackage)
          |> RunAsync.List.joinAll;
        return({Solution.pkg, bag});
      };

      let buildDependencies =
        Hashtbl.fold(
          ((name, version), (manifest, deps, solvedDeps), result) => [
            makeFullPackage(
              name,
              version,
              manifest,
              deps,
              solvedDeps,
              buildToVersions,
            ),
            ...result,
          ],
          buildVersionMap,
          [],
        );
      let root =
        makeFullPackage(
          "*root*",
          Solution.Version.LocalPath(Path.v("./")),
          manifest,
          depsByKind,
          solvedDeps,
          buildToVersions,
        );
      let%bind root = lockdownRootPackage(root);
      let%bind buildDependencies =
        buildDependencies
        |> List.map(lockdownRootPackage)
        |> RunAsync.List.joinAll;
      let env = {Solution.root, buildDependencies};
      return(env);
    }
  );
