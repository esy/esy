module Path = EsyLib.Path;
module RunAsync = EsyLib.RunAsync;
module Config = Shared.Config;
module Solution = Shared.Solution;

let fetch = (config: Config.t, solution: Solution.t) => {
  open RunAsync.Syntax;

  /* Collect packages which from the solution */
  let packagesToFetch = {
    let pkgs = Hashtbl.create(100);

    let add = (pkg: Solution.pkg) =>
      Hashtbl.replace(pkgs, (pkg.name, pkg.version), pkg);

    List.iter(add, solution.root.bag);

    List.iter(
      ({Solution.pkg, bag}) => {
        add(pkg);
        List.iter(add, bag);
      },
      solution.buildDependencies,
    );

    pkgs;
  };

  let nodeModulesPath = Path.(config.basePath / "node_modules");
  let packageInstallPath = pkg =>
    Path.(append(nodeModulesPath, v(pkg.Solution.name)));

  let%bind _ = Fs.rmPath(nodeModulesPath);
  let%bind () = Fs.createDirectory(nodeModulesPath);

  Hashtbl.iter(
    ((name, version), pkg) => {
      let dst = packageInstallPath(pkg);
      let pkg =
        Storage.fetch(~config, ~name, ~version, ~source=pkg.Solution.source)
        |> RunAsync.runExn(~err="error fetching package");
      Storage.install(~config, ~dst, pkg)
      |> RunAsync.runExn(~err="error installing package");
    },
    packagesToFetch,
  );

  return();
};
