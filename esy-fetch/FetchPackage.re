open RunAsync.Syntax;
type kind =
  | Fetched(DistStorage.fetchedDist)
  | Installed(Path.t)
  | Linked(Path.t);

type installation = unit;

/* fetch any of the dists for the package */
let fetch' = (sandbox, pkg, dists, gitUsername, gitPassword) => {
  let rec fetchAny = (errs, alternatives) =>
    switch (alternatives) {
    | [dist, ...rest] =>
      let fetched =
        DistStorage.fetch(
          sandbox.Sandbox.cfg,
          sandbox.spec,
          dist,
          gitUsername,
          gitPassword,
          (),
        );
      switch%lwt (fetched) {
      | Ok(fetched) => return(fetched)
      | Error(err) => fetchAny([(dist, err), ...errs], rest)
      };
    | [] =>
      let ppErr = (fmt, (source, err)) =>
        Fmt.pf(
          fmt,
          "source: %a%a",
          EsyPackageConfig.Dist.pp,
          source,
          Run.ppErrorSimple,
          err,
        );
      errorf(
        "Unable to fetch %a@\n%a",
        Package.pp,
        pkg,
        Fmt.(list(~sep=any("\n"), ppErr)),
        errs,
      );
    };

  fetchAny([], dists);
};

let fetch = (sandbox, pkg, gitUsername, gitPassword) => {
  /*** TODO: need to sync here so no two same tasks are running at the same time */
  switch (pkg.Package.source) {
  | Link({path, _}) =>
    let path =
      EsyPackageConfig.DistPath.toPath(sandbox.Sandbox.spec.path, path);
    return(Linked(path));
  | Install({source: (main, mirrors), opam: _}) =>
    let* cached =
      switch (PackagePaths.cachedTarballPath(sandbox, pkg)) {
      | None => return(None)
      | Some(cachedTarballPath) =>
        if%bind (Fs.exists(cachedTarballPath)) {
          let%lwt () =
            Logs_lwt.debug(m =>
              m("fetching %a: found cached tarball", Package.pp, pkg)
            );
          let dist = DistStorage.ofCachedTarball(cachedTarballPath);
          return(Some(Fetched(dist)));
        } else {
          let%lwt () =
            Logs_lwt.debug(m =>
              m("fetching %a: making cached tarball", Package.pp, pkg)
            );
          let dists = [main, ...mirrors];
          let* dist = fetch'(sandbox, pkg, dists, gitUsername, gitPassword);
          let* dist = DistStorage.cache(dist, cachedTarballPath);
          return(Some(Fetched(dist)));
        }
      };

    let path = PackagePaths.installPath(sandbox, pkg);
    if%bind (Fs.exists(path)) {
      let%lwt () =
        Logs_lwt.debug(m => m("fetching %a: installed", Package.pp, pkg));
      return(Installed(path));
    } else {
      switch (cached) {
      | Some(cached) => return(cached)
      | None =>
        let%lwt () =
          Logs_lwt.debug(m => m("fetching %a: fetching", Package.pp, pkg));
        let dists = [main, ...mirrors];
        let* dist = fetch'(sandbox, pkg, dists, gitUsername, gitPassword);
        return(Fetched(dist));
      };
    };
  };
};

let copyFiles = (sandbox, pkg, path) => {
  open Package;

  let* filesOfOpam =
    switch (pkg.source) {
    | Link(_)
    | Install({opam: None, _}) => return([])
    | Install({opam: Some(opam), _}) =>
      EsyPackageConfig.PackageSource.opamfiles(opam)
    };

  let* filesOfOverride =
    Overrides.fetch(
      sandbox.Sandbox.cfg,
      sandbox.Sandbox.spec,
      pkg.Package.overrides,
    );

  let extraSources = Package.extraSources(pkg);
  let tempPath = SandboxSpec.tempPath(sandbox.spec);
  let* () =
    Fs.withTempDir(~tempPath, stagePath => {
      ExtraSources.fetch(~cachedSourcesPath=path, ~stagePath, extraSources)
    });
  RunAsync.List.mapAndWait(
    ~f=EsyPackageConfig.File.placeAt(path),
    filesOfOpam @ filesOfOverride,
  );
};

let install' = (~stagePath, sandbox, pkg, fetched) => {
  let* () =
    RunAsync.ofLwt @@ Logs_lwt.debug(m => m("unpacking %a", Package.pp, pkg));

  let* () =
    RunAsync.contextf(
      DistStorage.unpack(fetched, stagePath),
      "unpacking %a at %a",
      Package.pp,
      pkg,
      Path.pp,
      stagePath,
    );

  copyFiles(sandbox, pkg, stagePath);
};

let install = (~fetchedKind, ~stagePath, sandbox, pkg) =>
  RunAsync.contextf(
    switch (fetchedKind) {
    | Linked(_)
    | Installed(_) => return()
    | Fetched(fetched) => install'(~stagePath, sandbox, pkg, fetched)
    },
    "installing %a",
    Package.pp,
    pkg,
  );
