module PathSet = Set.Make(Path);
module ConfigPath = Config.ConfigPath;

[@deriving show]
type t = {
  root: Package.t,
  scripts: Package.Scripts.t,
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
  let resolutionCache = Memoize.make(~size=200, ());
  let resolvePackageCached = (pkgName, basedir) => {
    let key = (pkgName, basedir);
    let compute = _ => resolvePackage(pkgName, basedir);
    Memoize.compute(resolutionCache, key, compute);
  };
  let packageCache = Memoize.make(~size=200, ());

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
          if (List.mem(depPackagePath, ~set=stack)) {
            if (ignoreCircularDep) {
              Lwt.return_ok((pkgName, `Ignored));
            } else {
              Lwt.return_error((pkgName, "circular dependency"));
            };
          } else {
            switch%lwt (loadPackageCached(depPackagePath, [path, ...stack])) {
            | Ok((result, _json)) => Lwt.return_ok((pkgName, result))
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
      Lwt.return(List.fold_left(~f, ~init=prevDependencies, dependencies));
    };

    let pathToEsyLink = Path.(path / "_esylink");

    let loadDependencies = manifest => {
      let (>>=) = Lwt.(>>=);
      let ignoreCircularDep = Option.isNone(manifest.Package.Manifest.esy);
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
    };

    let packageOfManifest = (~sourcePath, manifest, manifestPath, json) => {
      manifestInfo := PathSet.add(manifestPath, manifestInfo^);
      let%lwt dependencies = loadDependencies(manifest);
      switch (manifest.Package.Manifest.esy) {
      | None => return((`NonEsyPkg(dependencies), json))
      | Some(esyManifest) =>
        let sourceType = {
          let hasDepWithSourceTypeDevelopment =
            List.exists(
              ~f=
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
        return((`EsyPkg(pkg), json));
      };
    };

    let%bind sourcePath =
      if%bind (Fs.exists(pathToEsyLink)) {
        let%bind path = Fs.readFile(pathToEsyLink);
        return(Path.v(String.trim(path)));
      } else {
        return(path);
      };

    switch%bind (Package.Manifest.ofDir(sourcePath)) {
    | Some((manifest, manifestPath, json)) =>
      packageOfManifest(~sourcePath, manifest, manifestPath, json)
    | None => error("unable to find manifest")
    };
  }
  and loadPackageCached = (path: Path.t, stack) => {
    let compute = _ => loadPackage(path, stack);
    Memoize.compute(packageCache, path, compute);
  };
  switch%bind (loadPackageCached(cfg.sandboxPath, [])) {
  | (`EsyPkg(root), json) =>
    let%bind manifestInfo =
      manifestInfo^
      |> PathSet.elements
      |> List.map(~f=path => {
           let%bind stat = Fs.stat(path);
           return((path, stat.Unix.st_mtime));
         })
      |> RunAsync.List.joinAll;
    let%bind scripts =
      Package.Scripts.ParseManifest.parse(json)
      |> Run.ofStringError
      |> RunAsync.ofRun;
    let sandbox = {root, scripts, manifestInfo};
    return(sandbox);
  | _ => error("root package missing esy config")
  };
};
