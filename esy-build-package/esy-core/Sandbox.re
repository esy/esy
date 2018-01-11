module Package = {
  [@deriving show]
  type t = {
    id: string,
    name: string,
    version: string,
    dependencies: list(dependency),
    buildCommands: Manifest.CommandList.t,
    installCommands: Manifest.CommandList.t,
    buildType: Manifest.EsyManifest.buildType,
    exportedEnv: Manifest.ExportedEnv.t
  }
  and dependency =
    | Dependency(t)
    | DevDependency(t)
    | InvalidDependency{
        packageName: string,
        reason: string
      };
};

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

module Cache = {
  let create = (~size=100) => {
    let cache = Hashtbl.create(size);
    let lookup = (key, compute) =>
      try (Hashtbl.find(cache, key)) {
      | Not_found =>
        let promise = compute();
        Hashtbl.add(cache, key, promise);
        promise;
      };
    lookup;
  };
};

module StringMap = Map.Make(String);

let ofDir = path => {
  let resolutionCache = Cache.create(~size=200);
  let resolvePackageCached = (packageName, basedir) => {
    let key = (packageName, basedir);
    let compute = () => resolvePackage(packageName, basedir);
    resolutionCache(key, compute);
  };
  let packageCache = Cache.create(~size=200);
  let rec loadPackage = (path: EsyLib.Path.t) => {
    let resolveDep = (depPackageName: string) =>
      switch%lwt (resolvePackageCached(depPackageName, path)) {
      | Some(depPackagePath) =>
        switch%lwt (loadPackageCached(depPackagePath)) {
        | Ok(pkg) => Lwt.return(Package.Dependency(pkg))
        | Error(reason) =>
          Lwt.return(
            Package.InvalidDependency({packageName: depPackageName, reason})
          )
        }
      | None =>
        Lwt.return(
          Package.InvalidDependency({
            packageName: depPackageName,
            reason: "cannot resolve dependency"
          })
        )
      };
    let%lwt manifest = Manifest.ofDir(path);
    switch manifest {
    | Some(Ok(manifest)) =>
      let%lwt dependencies =
        StringMap.bindings(manifest.dependencies)
        |> List.map(((packageName, _)) => packageName)
        |> Lwt_list.map_p(resolveDep);
      let pkg =
        Package.{
          id: manifest.name,
          name: manifest.name,
          version: manifest.version,
          dependencies,
          buildCommands: manifest.esy.build,
          installCommands: manifest.esy.install,
          buildType: manifest.esy.buildsInSource,
          exportedEnv: manifest.esy.exportedEnv
        };
      Lwt.return(Ok(pkg));
    | Some(Error(err)) =>
      let path = Path.to_string(path);
      let msg =
        Printf.sprintf("error parsing manifest '%s' at: %s", err, path);
      Lwt.return(Error(msg));
    | _ => Lwt.return(Error("no manifest found at: " ++ Path.to_string(path)))
    };
  }
  and loadPackageCached = (path: Path.t) => {
    let compute = () => loadPackage(path);
    packageCache(path, compute);
  };
  loadPackageCached(path);
};
