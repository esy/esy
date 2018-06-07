let unsatisfied = (map, req) =>
  switch (Hashtbl.find(map, PackageInfo.Req.name(req))) {
  | exception Not_found => true
  | versions =>
    !
      List.exists(
        v => SolveUtils.satisfies(v, PackageInfo.Req.spec(req)),
        versions,
      )
  };

let settleBuildDeps = (~cfg, ~cache, solvedDeps, requestedBuildDeps) => {
  let allTransitiveBuildDeps =
    solvedDeps
    |> List.map(pkg => pkg.Package.dependencies)
    |> List.map(deps => deps.PackageInfo.DependenciesInfo.buildDependencies)
    |> List.concat;
  /* let allTransitiveBuildDeps = allNeededBuildDeps @ (
       solvedTargets |> List.map(((_, deps)) => getBuildDeps(deps)) |> List.concat |> List.concat
     ); */
  let buildDepsToInstall = allTransitiveBuildDeps @ requestedBuildDeps;
  let nameToVersions = Hashtbl.create(100);
  let versionMap = Hashtbl.create(100);
  let rec loop = (buildDeps: PackageInfo.Dependencies.t) => {
    let toAdd = buildDeps |> List.filter(unsatisfied(nameToVersions));
    if (toAdd != []) {
      let solved =
        SolveDeps.solveLoose(
          ~cfg,
          ~cache,
          ~requested=toAdd,
          ~current=nameToVersions,
          ~deep=false,
        )
        |> RunAsync.runExn(~err="error solving deps");
      solved
      |> List.map((pkg: Package.t) =>
           if (! Hashtbl.mem(versionMap, (pkg.name, pkg.version))) {
             Hashtbl.replace(
               nameToVersions,
               pkg.name,
               [
                 pkg.version,
                 ...Hashtbl.mem(nameToVersions, pkg.name) ?
                      Hashtbl.find(nameToVersions, pkg.name) : [],
               ],
             );
             let solvedDeps =
               SolveDeps.solve(
                 ~cfg,
                 ~cache,
                 ~requested=pkg.dependencies.dependencies,
               )
               |> RunAsync.runExn(~err="error solving deps");
             Hashtbl.replace(
               versionMap,
               (pkg.name, pkg.version),
               (pkg, solvedDeps),
             );
             let childBuilds =
               solvedDeps
               |> List.map(pkg => pkg.Package.dependencies)
               |> List.map(deps =>
                    deps.PackageInfo.DependenciesInfo.buildDependencies
                  )
               |> List.concat;
             childBuilds @ pkg.dependencies.buildDependencies;
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

let solve = (~cfg, pkg: Package.t) =>
  RunAsync.Syntax.(
    {
      let%bind () = SolveUtils.checkRepositories(cfg);
      let cache = SolveState.Cache.make(~cfg, ());
      let solvedDeps =
        SolveDeps.solve(
          ~cfg,
          ~cache,
          ~requested=pkg.dependencies.dependencies,
        )
        |> RunAsync.runExn(~err="error solving deps");
      let (buildVersionMap, _buildToVersions) =
        settleBuildDeps(
          ~cfg,
          ~cache,
          solvedDeps,
          pkg.dependencies.buildDependencies,
        );

      let makePkg = (pkg: Package.t) => {
        let%bind source = SolveUtils.lockDownSource(pkg.source);
        return({
          Solution.name: pkg.name,
          version: pkg.version,
          source,
          opam: pkg.opam,
        });
      };

      let makeRootPkg = (pkg, deps) => {
        let%bind bag =
          deps
          |> List.map((pkg: Package.t) => makePkg(pkg))
          |> RunAsync.List.joinAll;
        return({Solution.pkg, bag});
      };

      let%bind root = {
        let%bind pkg = makePkg(pkg);
        makeRootPkg(pkg, solvedDeps);
      };

      let%bind buildDependencies =
        Hashtbl.fold(
          (_key, (pkg, deps), result) => [(pkg, deps), ...result],
          buildVersionMap,
          [],
        )
        |> List.map(((pkg, deps)) => {
             let%bind pkg = makePkg(pkg);
             makeRootPkg(pkg, deps);
           })
        |> RunAsync.List.joinAll;

      let env = {Solution.root, buildDependencies};
      return(env);
    }
  );
