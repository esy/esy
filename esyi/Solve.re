module VersionSpec = PackageInfo.VersionSpec;

let solve = (~cfg, ~resolutions, pkg: Package.t) =>
  RunAsync.Syntax.(
    {
      let%bind cache = SolveState.Cache.make(~cfg, ());
      let%bind deps =
        SolveDeps.solve(
          ~cfg,
          ~cache,
          ~resolutions,
          ~from=pkg,
          pkg.dependencies.dependencies,
        );

      let solution = {
        let makePkg = (pkg: Package.t) => {
          Solution.name: pkg.name,
          version: pkg.version,
          source: pkg.source,
          opam: pkg.opam,
        };

        let pkg = makePkg(pkg);
        let bag = List.map(~f=(pkg: Package.t) => makePkg(pkg), deps);
        {Solution.pkg, bag};
      };

      return(solution);
    }
  );
