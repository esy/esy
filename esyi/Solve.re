module Cache = SolveState.Cache;
module Source = PackageInfo.Source;
module Version = PackageInfo.Version;
module SourceSpec = PackageInfo.SourceSpec;
module VersionSpec = PackageInfo.VersionSpec;
module Req = PackageInfo.Req;
module Universe = SolveState.Universe;

let getPackageCached =
    (~state: SolveState.t, name: string, version: PackageInfo.Version.t) => {
  open RunAsync.Syntax;
  let key = (name, version);
  Cache.Packages.compute(
    state.cache.pkgs,
    key,
    _ => {
      let%bind manifest =
        switch (version) {
        | Version.Source(Source.LocalPath(_)) => error("not implemented")
        | Version.Source(Git(_)) => error("not implemented")
        | Version.Source(Github(user, repo, ref)) =>
          switch%bind (Package.Github.getManifest(~user, ~repo, ~ref, ())) {
          | Package.PackageJson(manifest) =>
            /* We rewrite a package name as per request */
            return(Package.PackageJson({...manifest, name}))
          | manifest =>
            /* TODO: decide if we need to rewrite package name as well */
            return(manifest)
          }
        | Version.Source(Source.NoSource) => error("no source")
        | Version.Source(Source.Archive(_)) => error("not implemented")

        | Version.Npm(version) =>
          let%bind manifest =
            NpmRegistry.version(~cfg=state.cfg, name, version);
          return(Package.PackageJson(manifest));

        | Version.Opam(version) =>
          let name = OpamFile.PackageName.ofNpmExn(name);
          switch%bind (
            OpamRegistry.version(state.cache.opamRegistry, ~name, ~version)
          ) {
          | Some(manifest) => return(Package.Opam(manifest))
          | None =>
            error(
              "no such opam package: " ++ OpamFile.PackageName.toString(name),
            )
          };
        };
      let%bind pkg = RunAsync.ofRun(Package.make(~version, manifest));
      return(pkg);
    },
  );
};

let getAvailableVersions = (~state: SolveState.t, req: Req.t) => {
  open RunAsync.Syntax;
  let cache = state.cache;
  let name = Req.name(req);
  let spec = Req.spec(req);

  switch (spec) {
  | VersionSpec.Npm(formula) =>
    let%bind available =
      Cache.NpmPackages.compute(
        cache.availableNpmVersions,
        name,
        name => {
          let%lwt () = Logs_lwt.app(m => m("Resolving %s", name));
          let%bind versions = NpmRegistry.versions(~cfg=state.cfg, name);
          let () = {
            let cacheManifest = ((version, manifest)) => {
              let version = PackageInfo.Version.Npm(version);
              let key = (name, version);
              Cache.Packages.ensureComputed(cache.pkgs, key, _ =>
                Lwt.return(
                  Package.make(~version, Package.PackageJson(manifest)),
                )
              );
            };
            List.iter(~f=cacheManifest, versions);
          };
          return(versions);
        },
      );

    available
    |> List.sort(~cmp=((va, _), (vb, _)) =>
         NpmVersion.Version.compare(va, vb)
       )
    |> List.filter(~f=((version, _json)) =>
         NpmVersion.Formula.DNF.matches(formula, ~version)
       )
    |> List.map(~f=((version, _json)) => {
         let version = PackageInfo.Version.Npm(version);
         let%bind pkg = getPackageCached(~state, name, version);
         return(pkg);
       })
    |> RunAsync.List.joinAll;

  | VersionSpec.Opam(semver) =>
    let%bind available =
      Cache.OpamPackages.compute(
        cache.availableOpamVersions,
        name,
        name => {
          let%lwt () = Logs_lwt.app(m => m("Resolving %s", name));
          let%bind opamName =
            RunAsync.ofRun(OpamFile.PackageName.ofNpm(name));
          let%bind info =
            OpamRegistry.versions(state.cache.opamRegistry, ~name=opamName);
          return(info);
        },
      );

    let available =
      available
      |> List.sort(~cmp=((va, _), (vb, _)) =>
           OpamVersion.Version.compare(va, vb)
         );

    let matched =
      available
      |> List.filter(~f=((version, _path)) =>
           OpamVersion.Formula.DNF.matches(semver, ~version)
         );

    let matched =
      if (matched == []) {
        available
        |> List.filter(~f=((version, _path)) =>
             OpamVersion.Formula.DNF.matches(semver, ~version)
           );
      } else {
        matched;
      };

    matched
    |> List.map(~f=((version, _path)) => {
         let version = PackageInfo.Version.Opam(version);
         let%bind pkg = getPackageCached(~state, name, version);
         return(pkg);
       })
    |> RunAsync.List.joinAll;

  | VersionSpec.Source(SourceSpec.Github(user, repo, ref) as srcSpec) =>
    let%bind source =
      Cache.Sources.compute(
        state.cache.sources,
        srcSpec,
        _ => {
          let%lwt () =
            Logs_lwt.app(m => m("Resolving %s", Req.toString(req)));
          let%bind ref =
            switch (ref) {
            | Some(ref) => return(ref)
            | None =>
              let remote =
                Printf.sprintf("https://github.com/%s/%s", user, repo);
              Git.lsRemote(~remote, ());
            };
          return(Source.Github(user, repo, ref));
        },
      );

    let version = Version.Source(source);
    let%bind pkg = getPackageCached(~state, name, version);
    return([pkg]);

  | VersionSpec.Source(SourceSpec.Git(_)) =>
    let%lwt () = Logs_lwt.app(m => m("Resolving %s", Req.toString(req)));
    error("git dependencies are not supported");

  | VersionSpec.Source(SourceSpec.NoSource) =>
    let%lwt () = Logs_lwt.app(m => m("Resolving %s", Req.toString(req)));
    error("no source dependencies are not supported");

  | VersionSpec.Source(SourceSpec.Archive(_)) =>
    let%lwt () = Logs_lwt.app(m => m("Resolving %s", Req.toString(req)));
    error("archive dependencies are not supported");

  | VersionSpec.Source(SourceSpec.LocalPath(p)) =>
    let%lwt () = Logs_lwt.app(m => m("Resolving %s", Req.toString(req)));
    let version = Version.Source(Source.LocalPath(p));
    let%bind pkg = getPackageCached(~state, name, version);
    return([pkg]);
  };
};

let initState = (~cfg, ~cache=?, ~resolutions, root) => {
  open RunAsync.Syntax;

  let rewritePkgWithResolutions = (pkg: Package.t) => {
    let rewriteReq = req =>
      switch (PackageInfo.Resolutions.apply(resolutions, req)) {
      | Some(req) => req
      | None => req
      };
    {
      ...pkg,
      dependencies: {
        ...pkg.dependencies,
        dependencies: List.map(~f=rewriteReq, pkg.dependencies.dependencies),
      },
    };
  };

  let%bind state = SolveState.make(~cache?, ~cfg, ());

  let rec addPkg = (pkg: Package.t) =>
    if (! Universe.mem(~pkg, state.SolveState.universe)) {
      let pkg = rewritePkgWithResolutions(pkg);
      state.SolveState.universe =
        Universe.add(~pkg, state.SolveState.universe);

      pkg.dependencies.dependencies
      |> List.map(~f=addReq)
      |> RunAsync.List.waitAll;
    } else {
      return();
    }
  and addReq = req => {
    let%bind versions =
      getAvailableVersions(~state, req)
      |> RunAsync.withContext("processing request: " ++ Req.toString(req));

    List.map(~f=addPkg, versions) |> RunAsync.List.waitAll;
  };

  let%bind () = addPkg(root);
  return(state);
};

let solve = (~cfg, ~resolutions, root: Package.t) =>
  RunAsync.Syntax.(
    {
      let%bind state = initState(~cfg, ~resolutions, root);

      let%bind dependencies =
        switch (SolveState.runSolver(~univ=state.SolveState.universe, root)) {
        | None => error("Unable to resolve dependencies")
        | Some(packages) => return(packages)
        };
      let solution = Solution.make(~root, ~dependencies);

      return(solution);
    }
  );
