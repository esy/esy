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
      let extraSources = Package.extraSources(pkg);
      let fetched =
        DistStorage.fetch(
          sandbox.Sandbox.cfg,
          sandbox.spec,
          dist,
          ~extraSources,
          gitUsername,
          gitPassword,
          (),
        );
      switch%lwt (fetched) {
      | Ok(fetched) => return(fetched)
      | Error(err) => fetchAny([(dist, err), ...errs], rest)
      };
    | [] =>
      let%lwt () =
        Esy_logs_lwt.err(m => {
          let ppErr = (fmt, (source, err)) =>
            Fmt.pf(
              fmt,
              "source: %a@\nerror: %a",
              EsyPackageConfig.Dist.pp,
              source,
              Run.ppError,
              err,
            );

          m(
            "unable to fetch %a:@[<v 2>@\n%a@]",
            Package.pp,
            pkg,
            Fmt.(list(~sep=any("@\n"), ppErr)),
            errs,
          );
        });
      error("installation error");
    };

  fetchAny([], dists);
};

let fetch = (sandbox, pkg, gitUsername, gitPassword) => {
  /*** TODO: need to sync here so no two same tasks are running at the same time */
  RunAsync.contextf(
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
              Esy_logs_lwt.debug(m =>
                m("fetching %a: found cached tarball", Package.pp, pkg)
              );
            let dist = DistStorage.ofCachedTarball(cachedTarballPath);
            return(Some(Fetched(dist)));
          } else {
            let%lwt () =
              Esy_logs_lwt.debug(m =>
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
          Esy_logs_lwt.debug(m =>
            m("fetching %a: installed", Package.pp, pkg)
          );
        return(Installed(path));
      } else {
        switch (cached) {
        | Some(cached) => return(cached)
        | None =>
          let%lwt () =
            Esy_logs_lwt.debug(m =>
              m("fetching %a: fetching", Package.pp, pkg)
            );
          let dists = [main, ...mirrors];
          let* dist = fetch'(sandbox, pkg, dists, gitUsername, gitPassword);
          return(Fetched(dist));
        };
      };
    },
    "fetching %a",
    Package.pp,
    pkg,
  );
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

  RunAsync.List.mapAndWait(
    ~f=EsyPackageConfig.File.placeAt(path),
    filesOfOpam @ filesOfOverride,
  );
};

let install' = (~stagePath, sandbox, pkg, fetched) => {
  let* () =
    RunAsync.ofLwt @@
    Esy_logs_lwt.debug(m => m("unpacking %a", Package.pp, pkg));

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
