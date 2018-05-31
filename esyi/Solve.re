let unsatisfied = (map, (name, range)) =>
  switch (Hashtbl.find(map, name)) {
  | exception Not_found => true
  | versions => ! List.exists(v => SolveUtils.satisfies(v, range), versions)
  };

let findSatisfyingInMap = (map, name, range) =>
  List.find(v => SolveUtils.satisfies(v, range), Hashtbl.find(map, name));

let justDepsn = ((_, _, _, deps)) => deps;

module StringMap =
  Map.Make({
    type t = string;
    let compare = compare;
  });

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
        deps.Types.runtime
        |> List.map(((name, range)) =>
             (name, range, Hashtbl.find(nameToVersion, name))
           ),
      build:
        deps.Types.build
        |> List.map(((name, range)) =>
             (name, range, findSatisfyingInMap(buildToVersions, name, range))
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
               deps.Types.runtime
               |> List.map(((name, range)) =>
                    (name, range, Hashtbl.find(nameToVersion, name))
                  ),
             build:
               deps.Types.build
               |> List.map(((name, range)) =>
                    (
                      name,
                      range,
                      findSatisfyingInMap(buildToVersions, name, range),
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
    |> List.map(deps => deps.Types.build)
    |> List.concat;
  /* let allTransitiveBuildDeps = allNeededBuildDeps @ (
       solvedTargets |> List.map(((_, deps)) => getBuildDeps(deps)) |> List.concat |> List.concat
     ); */
  let buildDepsToInstall = allTransitiveBuildDeps @ requestedBuildDeps;
  let nameToVersions = Hashtbl.create(100);
  let versionMap = Hashtbl.create(100);
  let rec loop = buildDeps => {
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
                 ~requested=deps.Types.runtime,
               );
             Hashtbl.replace(
               versionMap,
               (name, version),
               (manifest, deps, solvedDeps),
             );
             let childBuilds =
               solvedDeps
               |> List.map(justDepsn)
               |> List.map(deps => deps.Types.build)
               |> List.concat;
             childBuilds @ deps.Types.build;
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
        SolveDeps.solve(~config, ~cache, ~requested=depsByKind.runtime);
      let (buildVersionMap, buildToVersions) =
        settleBuildDeps(~config, cache, solvedDeps, depsByKind.build);

      let lockdownFullPackage = full => {
        let%bind source = SolveUtils.lockDownSource(full.Env.source);
        return({
          Solution.name: full.Env.name,
          version: full.Env.version,
          source,
          requested: full.Env.requested,
          runtime: full.runtime,
          build: full.Env.build,
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
