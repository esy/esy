module PackageSet =
  Set.Make({
    type t = Solution.Record.t;
    let compare = (pkga, pkgb) => {
      let c =
        String.compare(pkga.Solution.Record.name, pkgb.Solution.Record.name);
      if (c == 0) {
        PackageInfo.Version.compare(pkga.version, pkga.version);
      } else {
        c;
      };
    };
  });

type layout = list((Path.t, Solution.Record.t));

let packagesOfSolution = solution => {
  let rec addRoot = (pkgs, root) =>
    pkgs
    |> PackageSet.add(root.Solution.root, _)
    |> List.fold_left(~f=addRoot, ~init=_, root.Solution.dependencies);

  let pkgs =
    List.fold_left(
      ~f=addRoot,
      ~init=PackageSet.empty,
      solution.Solution.dependencies,
    );

  PackageSet.elements(pkgs);
};

let layoutOfSolution = (basePath, solution) : layout => {
  let rec layoutRoot = (basePath, layout, root) => {
    let recordPath =
      Path.(basePath / "node_modules" /\/ v(root.Solution.root.name));
    let layout = [(recordPath, root.Solution.root), ...layout];
    List.fold_left(
      ~f=layoutRoot(recordPath),
      ~init=layout,
      root.Solution.dependencies,
    );
  };

  let layout =
    List.fold_left(
      ~f=layoutRoot(basePath),
      ~init=[],
      solution.Solution.dependencies,
    );

  layout;
};

let checkSolutionInstalled = (~cfg: Config.t, solution: Solution.t) => {
  open RunAsync.Syntax;

  let layout = layoutOfSolution(cfg.basePath, solution);

  let%bind installed =
    layout
    |> List.map(~f=((path, _)) => Fs.exists(path))
    |> RunAsync.List.joinAll;
  return(List.for_all(~f=installed => installed, installed));
};

let fetch = (~cfg: Config.t, solution: Solution.t) => {
  open RunAsync.Syntax;

  /* Collect packages which from the solution */
  let packagesToFetch = packagesOfSolution(solution);

  let nodeModulesPath = Path.(cfg.basePath / "node_modules");

  let%bind () = Fs.rmPath(nodeModulesPath);
  let%bind () = Fs.createDir(nodeModulesPath);

  let%lwt () =
    Logs_lwt.app(m => m("Checking if there are some packages to fetch..."));

  let%bind packagesFetched = {
    let queue = LwtTaskQueue.create(~concurrency=8, ());
    packagesToFetch
    |> List.map(~f=pkg => {
         let%bind fetchedPkg =
           LwtTaskQueue.submit(queue, () => FetchStorage.fetch(~cfg, pkg));
         return((pkg, fetchedPkg));
       })
    |> RunAsync.List.joinAll;
  };

  let%lwt () = Logs_lwt.app(m => m("Populating node_modules..."));

  let packageInstallPath = {
    let layout = layoutOfSolution(cfg.basePath, solution);
    pkg => {
      let (path, _) =
        List.find(
          ~f=
            ((_path, p)) =>
              String.equal(p.Solution.Record.name, pkg.Solution.Record.name)
              && PackageInfo.Version.equal(
                   p.Solution.Record.version,
                   pkg.Solution.Record.version,
                 ),
          layout,
        );
      path;
    };
  };

  let%bind () =
    RunAsync.List.processSeq(
      ~f=
        ((pkg, fetchedPkg)) => {
          let dst = packageInstallPath(pkg);
          FetchStorage.install(~cfg, ~dst, fetchedPkg);
        },
      packagesFetched,
    );

  return();
};
