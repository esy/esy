module PackageSet =
  Set.Make({
    type t = Solution.pkg;
    let compare = (pkga, pkgb) => {
      let c = String.compare(pkga.Solution.name, pkgb.Solution.name);
      if (c == 0) {
        PackageInfo.Version.compare(pkga.version, pkga.version);
      } else {
        c;
      };
    };
  });

let checkSolutionInstalled = (~cfg: Config.t, solution: Solution.t) => {
  open RunAsync.Syntax;

  let checkPkg = (pkg: Solution.pkg) => {
    let pkgPath = Path.(cfg.basePath / "node_modules" /\/ v(pkg.name));
    Fs.exists(pkgPath);
  };

  let checkRoot = root => {
    let%bind installed =
      root.Solution.bag |> List.map(~f=checkPkg) |> RunAsync.List.joinAll;
    return(List.for_all(~f=installed => installed, installed));
  };

  checkRoot(solution);
};

let fetch = (config: Config.t, solution: Solution.t) => {
  open RunAsync.Syntax;

  /* Collect packages which from the solution */
  let packagesToFetch = {
    let add = (pkgs, pkg: Solution.pkg) => PackageSet.add(pkg, pkgs);
    let addList = (pkgs, pkgsList) =>
      List.fold_left(~f=add, ~init=pkgs, pkgsList);

    let pkgs = PackageSet.empty |> addList(_, solution.bag);

    PackageSet.elements(pkgs);
  };

  let nodeModulesPath = Path.(config.basePath / "node_modules");
  let packageInstallPath = pkg =>
    Path.(append(nodeModulesPath, v(pkg.Solution.name)));

  let%bind () = Fs.rmPath(nodeModulesPath);
  let%bind () = Fs.createDir(nodeModulesPath);

  let%lwt () =
    Logs_lwt.app(m => m("Checking if there are some packages to fetch..."));

  let%bind packagesFetched = {
    let queue = LwtTaskQueue.create(~concurrency=8, ());
    packagesToFetch
    |> List.map(~f=pkg => {
         let%bind fetchedPkg =
           LwtTaskQueue.submit(queue, () => FetchStorage.fetch(~config, pkg));
         return((pkg, fetchedPkg));
       })
    |> RunAsync.List.joinAll;
  };

  let%lwt () = Logs_lwt.app(m => m("Populating node_modules..."));

  let%bind () =
    RunAsync.List.processSeq(
      ~f=
        ((pkg, fetchedPkg)) => {
          let dst = packageInstallPath(pkg);
          FetchStorage.install(~config, ~dst, fetchedPkg);
        },
      packagesFetched,
    );

  return();
};
