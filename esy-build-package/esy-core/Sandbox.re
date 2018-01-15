[@deriving show]
type t = {root: Package.t};

let rec resolvePackage = (packageName: string, basedir: Path.t) => {
  let packagePath = (packageName, basedir) =>
    Path.(basedir / "node_modules" / packageName);
  let scopedPackagePath = (scope, packageName, basedir) =>
    Path.(basedir / "node_modules" / scope / packageName);
  let packagePath =
    switch packageName.[0] {
    | '@' =>
      switch (String.split_on_char('/', packageName)) {
      | [scope, packageName] => scopedPackagePath(scope, packageName)
      | _ => packagePath(packageName)
      }
    | _ => packagePath(packageName)
    };
  let rec resolve = basedir => {
    let packagePath = packagePath(basedir);
    if%lwt (Io.exists(packagePath)) {
      Lwt.return(Some(packagePath));
    } else {
      let nextBasedir = Path.parent(basedir);
      if (nextBasedir === basedir) {
        Lwt.return(None);
      } else {
        resolve(nextBasedir);
      };
    };
  };
  resolve(basedir);
};

module StringMap = Map.Make(String);

let ofDir = path => {
  let resolutionCache = Memoize.create(~size=200);
  let resolvePackageCached = (packageName, basedir) => {
    let key = (packageName, basedir);
    let compute = () => resolvePackage(packageName, basedir);
    resolutionCache(key, compute);
  };
  let packageCache = Memoize.create(~size=200);
  let rec loadPackage = (path: EsyLib.Path.t) => {
    let resolveDep = (depPackageName: string) =>
      switch%lwt (resolvePackageCached(depPackageName, path)) {
      | Some(depPackagePath) =>
        switch%lwt (loadPackageCached(depPackagePath)) {
        | Ok(pkg) => Lwt.return_ok(pkg)
        | Error(reason) => Lwt.return_error((depPackageName, reason))
        }
      | None => Lwt.return_error((depPackageName, "cannot resolve dependency"))
      };
    let resolveDeps = (dependencies, make) => {
      let%lwt dependencies =
        StringMap.bindings(dependencies)
        |> List.map(((packageName, _)) => packageName)
        |> Lwt_list.map_p(resolveDep);
      Lwt.return(
        List.map(
          fun
          | Ok(pkg) => make(pkg)
          | Error((packageName, reason)) =>
            Package.InvalidDependency({packageName, reason}),
          dependencies
        )
      );
    };
    let%lwt manifest = Package.Manifest.ofDir(path);
    switch manifest {
    | Some(Ok(manifest)) =>
      let%lwt dependencies =
        resolveDeps(manifest.dependencies, pkg => Package.Dependency(pkg));
      let%lwt peerDependencies =
        resolveDeps(manifest.peerDependencies, pkg =>
          Package.PeerDependency(pkg)
        );
      let pkg =
        Package.{
          id: manifest.name,
          name: manifest.name,
          version: manifest.version,
          dependencies: dependencies @ peerDependencies,
          buildCommands: manifest.esy.build,
          installCommands: manifest.esy.install,
          buildType: manifest.esy.buildsInSource,
          sourceType: Package.Immutable,
          exportedEnv: manifest.esy.exportedEnv,
          sourcePath: path
        };
      Lwt.return_ok(pkg);
    | Some(Error(err)) =>
      let path = Path.to_string(path);
      let msg =
        Printf.sprintf("error parsing manifest '%s' at: %s", err, path);
      Lwt.return_error(msg);
    | _ => Lwt.return_error("no manifest found at: " ++ Path.to_string(path))
    };
  }
  and loadPackageCached = (path: Path.t) => {
    let compute = () => loadPackage(path);
    packageCache(path, compute);
  };
  loadPackageCached(path);
};
