module VersionSpec = PackageInfo.VersionSpec;

let solve = (~cfg, pkg: Package.t) =>
  RunAsync.Syntax.(
    {
      let%bind cache = SolveState.Cache.make(~cfg, ());
      let solvedDeps =
        SolveDeps.solve(
          ~cfg,
          ~cache,
          ~requested=pkg.dependencies.dependencies,
          ~resolutions,
        )
        |> RunAsync.runExn(~err="error solving deps");

      let makePkg = (pkg: Package.t) =>
        return({
          Solution.name: pkg.name,
          version: pkg.version,
          source: pkg.source,
          opam: pkg.opam,
        });

      let makeRootPkg = (pkg, deps) => {
        let%bind bag =
          deps
          |> List.map(~f=(pkg: Package.t) => makePkg(pkg))
          |> RunAsync.List.joinAll;
        return({Solution.pkg, bag});
      };

      let%bind root = {
        let%bind pkg = makePkg(pkg);
        makeRootPkg(pkg, solvedDeps);
      };

      return(root);
    }
  );
