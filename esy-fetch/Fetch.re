module Override = Override;
module Overrides = Overrides;
let collectPackagesOfSolution = (fetchDepsSubset, solution) => {
  let root = Solution.root(solution);

  let rec collect = ((seen, topo), pkg) =>
    if (Package.Set.mem(pkg, seen)) {
      (seen, topo);
    } else {
      let seen = Package.Set.add(pkg, seen);
      let (seen, topo) = collectDependencies((seen, topo), pkg);
      let topo = [pkg, ...topo];
      (seen, topo);
    }
  and collectDependencies = ((seen, topo), pkg) => {
    let dependencies =
      Solution.dependenciesBySpec(solution, fetchDepsSubset, pkg);
    List.fold_left(~f=collect, ~init=(seen, topo), dependencies);
  };

  let (_, topo) = collectDependencies((Package.Set.empty, []), root);
  (List.rev(topo), root);
};

let isInstalledWithInstallation =
    (fetchDepsSubset, sandbox: Sandbox.t, solution: Solution.t, installation) => {
  open RunAsync.Syntax;
  let rec checkSourcePaths =
    fun
    | [] => return(true)
    | [pkg, ...pkgs] =>
      switch (Installation.find(pkg.Package.id, installation)) {
      | None => return(false)
      | Some(path) =>
        if%bind (Fs.exists(path)) {
          checkSourcePaths(pkgs);
        } else {
          return(false);
        }
      };

  let rec checkCachedTarballPaths =
    fun
    | [] => return(true)
    | [pkg, ...pkgs] =>
      switch (PackagePaths.cachedTarballPath(sandbox, pkg)) {
      | None => checkCachedTarballPaths(pkgs)
      | Some(cachedTarballPath) =>
        if%bind (Fs.exists(cachedTarballPath)) {
          checkCachedTarballPaths(pkgs);
        } else {
          return(false);
        }
      };

  let rec checkInstallationEntry =
    fun
    | [] => true
    | [(pkgid, _path), ...rest] =>
      if (Solution.mem(solution, pkgid)) {
        checkInstallationEntry(rest);
      } else {
        false;
      };

  let (pkgs, _root) = collectPackagesOfSolution(fetchDepsSubset, solution);
  if%bind (checkSourcePaths(pkgs)) {
    if%bind (checkCachedTarballPaths(pkgs)) {
      return(checkInstallationEntry(Installation.entries(installation)));
    } else {
      return(false);
    };
  } else {
    return(false);
  };
};

let maybeInstallationOfSolution =
    (fetchDepsSubset, sandbox: Sandbox.t, solution: Solution.t) => {
  open RunAsync.Syntax;
  let installationPath = SandboxSpec.installationPath(sandbox.spec);
  switch%lwt (Installation.ofPath(installationPath)) {
  | Error(_)
  | Ok(None) => return(None)
  | Ok(Some(installation)) =>
    if%bind (isInstalledWithInstallation(
               fetchDepsSubset,
               sandbox,
               solution,
               installation,
             )) {
      return(Some(installation));
    } else {
      return(None);
    }
  };
};

let fetchPackages =
    (fetchDepsSubset, sandbox, solution, gitUsername, gitPassword) => {
  open RunAsync.Syntax;

  /* Collect packages which from the solution */
  let (pkgs, _root) = collectPackagesOfSolution(fetchDepsSubset, solution);

  let (report, finish) = Cli.createProgressReporter(~name="fetching", ());
  let* items = {
    let f = pkg => {
      let%lwt () = report("%a", Package.pp, pkg);
      let* fetch = FetchPackage.fetch(sandbox, pkg, gitUsername, gitPassword);
      return((pkg, fetch));
    };

    let fetchConcurrency =
      Option.orDefault(~default=40, sandbox.Sandbox.cfg.fetchConcurrency);

    let* items =
      RunAsync.List.mapAndJoin(~concurrency=fetchConcurrency, ~f, pkgs);
    let%lwt () = finish();
    return(items);
  };

  let fetched = {
    let f = (map, (pkg, fetch)) => Package.Map.add(pkg, fetch, map);

    List.fold_left(~f, ~init=Package.Map.empty, items);
  };

  return(fetched);
};

/**
   Creates [Installation.t] from list of packages. See Installation.re for
   [Installation.t]'s structure.

   To infer paths, it needs [sandbox] and [rootPackageID]
 */
let installationOfPkgs = (~rootPackageID, ~sandbox, pkgs) => {
  open Sandbox;
  open Package;
  let rootPackagePath = sandbox.spec.path;
  let init =
    Installation.empty |> Installation.add(rootPackageID, rootPackagePath);

  let f = (installation, pkg) => {
    let id = pkg.id;
    let path = PackagePaths.installPath(sandbox, pkg);
    Installation.add(id, path, installation);
  };

  List.fold_left(~f, ~init, pkgs);
};

let fetch = (fetchDepsSubset, sandbox, solution, gitUsername, gitPassword) => {
  open RunAsync.Syntax;

  /* Collect packages which from the solution */
  let (pkgs, root) = collectPackagesOfSolution(fetchDepsSubset, solution);

  /* Ensure all packages are available on disk. Download if necessary. */
  let* fetchedKindMap =
    fetchPackages(
      fetchDepsSubset,
      sandbox,
      solution,
      gitUsername,
      gitPassword,
    );

  let f = pkg => {
    let fetchedKind = Package.Map.find(pkg, fetchedKindMap);
    let* stagePath = {
      let path = PackagePaths.stagePath(sandbox, pkg);
      let* () = Fs.rmPath(path);
      return(path);
    };
    FetchPackage.install(~fetchedKind, ~stagePath, sandbox, pkg);
  };

  let fetchConcurrency =
    Option.orDefault(~default=40, sandbox.Sandbox.cfg.fetchConcurrency);

  /* Ensure downloaded packages are copied to the store */
  let* () = RunAsync.List.mapAndWait(~concurrency=fetchConcurrency, ~f, pkgs);

  /* Produce _esy/<sandbox>/installation.json */
  let installation =
    installationOfPkgs(~rootPackageID=root.Package.id, ~sandbox, pkgs);
  let* () =
    Fs.writeJsonFile(
      ~json=Installation.to_yojson(installation),
      SandboxSpec.installationPath(sandbox.spec),
    );

  /* JS packages need additional installation steps */
  let* () =
    Js.installBinaries(
      ~solution,
      ~fetchDepsSubset,
      ~sandbox,
      ~installation,
      ~fetchedKindMap,
    );

  let* () = Js.dumpPnp(~solution, ~fetchDepsSubset, ~sandbox, ~installation);

  let* () = Fs.rmPath(SandboxSpec.distPath(sandbox.Sandbox.spec));

  return();
};
