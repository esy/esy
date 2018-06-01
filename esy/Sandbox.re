module PathSet = Set.Make(Path);
module ConfigPath = Config.ConfigPath;

[@deriving show]
type t = {
  root: Package.t,
  manifestInfo: list((Path.t, float)),
};

let rec resolvePackage = (pkgName: string, basedir: Path.t) => {
  let packagePath = (pkgName, basedir) =>
    Path.(basedir / "node_modules" / pkgName);
  let scopedPackagePath = (scope, pkgName, basedir) =>
    Path.(basedir / "node_modules" / scope / pkgName);
  let packagePath =
    switch (pkgName.[0]) {
    | '@' =>
      switch (String.split_on_char('/', pkgName)) {
      | [scope, pkgName] => scopedPackagePath(scope, pkgName)
      | _ => packagePath(pkgName)
      }
    | _ => packagePath(pkgName)
    };
  let rec resolve = basedir => {
    open RunAsync.Syntax;
    let packagePath = packagePath(basedir);
    if%bind (Fs.exists(packagePath)) {
      return(Some(packagePath));
    } else {
      let nextBasedir = Path.parent(basedir);
      if (nextBasedir === basedir) {
        return(None);
      } else {
        resolve(nextBasedir);
      };
    };
  };
  resolve(basedir);
};

let ofDir = (cfg: Config.t) => {
  open RunAsync.Syntax;
  let manifestInfo = ref(PathSet.empty);
  let resolutionCache = Memoize.create(~size=200);
  let resolvePackageCached = (pkgName, basedir) => {
    let key = (pkgName, basedir);
    let compute = () => resolvePackage(pkgName, basedir);
    resolutionCache(key, compute);
  };
  let packageCache = Memoize.create(~size=200);
  let rec loadPackage = (path: Path.t, stack: list(Path.t)) => {
    let addDeps =
        (
          ~skipUnresolved=false,
          ~ignoreCircularDep,
          ~make,
          dependencies,
          prevDependencies,
        ) => {
      let resolve = (pkgName: string) =>
        switch%lwt (resolvePackageCached(pkgName, path)) {
        | Ok(Some(depPackagePath)) =>
          if (List.mem(depPackagePath, stack)) {
            if (ignoreCircularDep) {
              Lwt.return_ok((pkgName, `Ignored));
            } else {
              Lwt.return_error((pkgName, "circular dependency"));
            };
          } else {
            switch%lwt (loadPackageCached(depPackagePath, [path, ...stack])) {
            | Ok(result) => Lwt.return_ok((pkgName, result))
            | Error(err) => Lwt.return_error((pkgName, Run.formatError(err)))
            };
          }
        | Ok(None) => Lwt.return_ok((pkgName, `Unresolved))
        | Error(err) => Lwt.return_error((pkgName, Run.formatError(err)))
        };
      let%lwt dependencies =
        StringMap.bindings(dependencies)
        |> Lwt_list.map_s(((pkgName, _)) => resolve(pkgName));
      let f = dependencies =>
        fun
        | Ok((_, `EsyPkg(pkg))) => [make(pkg), ...dependencies]
        | Ok((_, `NonEsyPkg(transitiveDependencies))) =>
          transitiveDependencies @ dependencies
        | Ok((_, `Ignored)) => dependencies
        | Ok((pkgName, `Unresolved)) =>
          if (skipUnresolved) {
            dependencies;
          } else {
            [
              Package.InvalidDependency({
                pkgName,
                reason: "unable to resolve package",
              }),
              ...dependencies,
            ];
          }
        | Error((pkgName, reason)) => [
            Package.InvalidDependency({pkgName, reason}),
            ...dependencies,
          ];
      Lwt.return(
        ListLabels.fold_left(~f, ~init=prevDependencies, dependencies),
      );
    };
    switch%bind (Package.Manifest.ofDir(path)) {
    | Some((manifest, manifestPath)) =>
      let ignoreCircularDep = Option.isNone(manifest.Package.Manifest.esy);
      manifestInfo := PathSet.add(manifestPath, manifestInfo^);
      let (>>=) = Lwt.(>>=);
      let%lwt dependencies =
        Lwt.return([])
        >>= addDeps(
              ~ignoreCircularDep,
              ~make=pkg => Package.PeerDependency(pkg),
              manifest.Package.Manifest.peerDependencies,
            )
        >>= addDeps(
              ~ignoreCircularDep,
              ~make=pkg => Package.Dependency(pkg),
              manifest.Package.Manifest.dependencies,
            )
        >>= addDeps(
              ~ignoreCircularDep,
              ~make=pkg => Package.BuildTimeDependency(pkg),
              manifest.Package.Manifest.buildTimeDependencies,
            )
        >>= addDeps(
              ~ignoreCircularDep,
              ~skipUnresolved=true,
              ~make=pkg => Package.OptDependency(pkg),
              manifest.optDependencies,
            )
        >>= (
          dependencies =>
            if (Path.equal(cfg.sandboxPath, path)) {
              addDeps(
                ~ignoreCircularDep,
                ~skipUnresolved=true,
                ~make=pkg => Package.DevDependency(pkg),
                manifest.Package.Manifest.devDependencies,
                dependencies,
              );
            } else {
              Lwt.return(dependencies);
            }
        );
      switch (manifest.Package.Manifest.esy) {
      | None => return(`NonEsyPkg(dependencies))
      | Some(esyManifest) =>
        let sourceType = {
          let hasDepWithSourceTypeDevelopment =
            List.exists(
              fun
              | Package.Dependency(pkg)
              | Package.PeerDependency(pkg)
              | Package.BuildTimeDependency(pkg)
              | Package.OptDependency(pkg) =>
                pkg.sourceType == Package.SourceType.Development
              | Package.DevDependency(_)
              | Package.InvalidDependency(_) => false,
              dependencies,
            );
          switch (hasDepWithSourceTypeDevelopment, manifest._resolved) {
          | (true, _) => Package.SourceType.Development
          | (false, None) => Package.SourceType.Development
          | (false, Some(_)) => Package.SourceType.Immutable
          };
        };
        let%bind sourcePath = {
          let linkPath = Path.(path / "_esylink");
          if%bind (Fs.exists(linkPath)) {
            let%bind path = Fs.readFile(linkPath);
            path
            |> String.trim
            |> Path.of_string
            |> Run.ofBosError
            |> RunAsync.ofRun;
          } else {
            return(path);
          };
        };
        let pkg =
          Package.{
            id: Path.to_string(path),
            name: manifest.name,
            version: manifest.version,
            dependencies,
            buildCommands: esyManifest.Package.EsyManifest.build,
            installCommands: esyManifest.install,
            buildType: esyManifest.buildsInSource,
            sourceType,
            exportedEnv: esyManifest.exportedEnv,
            sandboxEnv: esyManifest.sandboxEnv,
            sourcePath: ConfigPath.ofPath(cfg, sourcePath),
            resolution: manifest._resolved,
          };
        return(`EsyPkg(pkg));
      };
    | None => error("unable to find manifest")
    };
  }
  and loadPackageCached = (path: Path.t, stack) => {
    let compute = () => loadPackage(path, stack);
    packageCache(path, compute);
  };
  switch%bind (loadPackageCached(cfg.sandboxPath, [])) {
  | `EsyPkg(root) =>
    let%bind manifestInfo =
      manifestInfo^
      |> PathSet.elements
      |> List.map(path => {
           let%bind stat = Fs.stat(path);
           return((path, stat.Unix.st_mtime));
         })
      |> RunAsync.List.joinAll;
    let sandbox = {root, manifestInfo};
    return(sandbox);
  | _ => error("root package missing esy config")
  };
};
