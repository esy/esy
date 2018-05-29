module Path = EsyLib.Path;
module RunAsync = EsyLib.RunAsync;
module Config = Shared.Config;
module Solution = Shared.Solution;
module Lockfile = Shared.Lockfile;

module PackageSet =
  Set.Make({
    type t = Solution.pkg;
    let compare = (pkga, pkgb) => {
      let c = String.compare(pkga.Solution.name, pkgb.Solution.name);
      if (c == 0) {
        Lockfile.compare_realVersion(pkga.version, pkga.version);
      } else {
        c;
      };
    };
  });

let fetch = (config: Config.t, solution: Solution.t) => {
  open RunAsync.Syntax;

  /* Collect packages which from the solution */
  let packagesToFetch = {
    let add = (pkgs, pkg: Solution.pkg) => PackageSet.add(pkg, pkgs);
    let addList = (pkgs, pkgsList) =>
      ListLabels.fold_left(~f=add, ~init=pkgs, pkgsList);

    let pkgs =
      PackageSet.empty
      |> addList(_, solution.root.bag)
      |> addList(
           _,
           solution.buildDependencies
           |> List.map(({Solution.pkg, bag}) => [pkg, ...bag])
           |> List.concat,
         );

    PackageSet.elements(pkgs);
  };

  let nodeModulesPath = Path.(config.basePath / "node_modules");
  let packageInstallPath = pkg =>
    Path.(append(nodeModulesPath, v(pkg.Solution.name)));

  let%bind _ = Fs.rmPath(nodeModulesPath);
  let%bind () = Fs.createDirectory(nodeModulesPath);

  Logs.app(m => m("Checking if there are some packages to fetch..."));

  let%bind packagesFetched =
    packagesToFetch
    |> List.map(pkg => {
         let%bind fetchedPkg =
           Storage.fetch(
             ~config,
             ~name=pkg.Solution.name,
             ~version=pkg.Solution.version,
             ~source=pkg.Solution.source,
           );
         return((pkg, fetchedPkg));
       })
    |> RunAsync.List.joinAll;

  Logs.app(m => m("Populating node_modules..."));

  let%bind () =
    RunAsync.List.processSeq(
      ~f=
        ((pkg, fetchedPkg)) => {
          let dst = packageInstallPath(pkg);
          Storage.install(~config, ~dst, fetchedPkg);
        },
      packagesFetched,
    );

  return();
};
