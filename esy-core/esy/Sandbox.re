module StringMap = Map.Make(String);

module ConfigPath = Config.ConfigPath;

[@deriving show]
type t = {root: Package.t};

let safePackageName = (name: string) => {
  let replaceAt = Str.regexp("@");
  let replaceUnderscore = Str.regexp("_+");
  let replaceSlash = Str.regexp("\\/");
  let replaceDot = Str.regexp("\\.");
  let replaceDash = Str.regexp("\\-");
  name
  |> String.lowercase_ascii
  |> Str.global_replace(replaceAt, "")
  |> Str.global_replace(replaceUnderscore, "__")
  |> Str.global_replace(replaceSlash, "__slash__")
  |> Str.global_replace(replaceDot, "__dot__")
  |> Str.global_replace(replaceDash, "_");
};

let packageId =
    (manifest: Package.Manifest.t, dependencies: list(Package.dependency)) => {
  let digest = (acc, update) => Digest.string(acc ++ "--" ++ update);
  let id =
    ListLabels.fold_left(
      ~f=digest,
      ~init="",
      [
        manifest.name,
        manifest.version,
        Package.CommandList.show(manifest.esy.build),
        Package.CommandList.show(manifest.esy.install),
        Package.BuildType.show(manifest.esy.buildsInSource),
        switch manifest._resolved {
        | Some(resolved) => resolved
        | None => ""
        }
      ]
    );
  let updateWithDepId = id =>
    fun
    | Package.Dependency(pkg)
    | Package.OptDependency(pkg)
    | Package.PeerDependency(pkg) => digest(id, pkg.id)
    | Package.InvalidDependency(_)
    | Package.DevDependency(_) => id;
  let id = ListLabels.fold_left(~f=updateWithDepId, ~init=id, dependencies);
  let hash = Digest.to_hex(id);
  let hash = String.sub(hash, 0, 8);
  safePackageName(manifest.name) ++ "-" ++ manifest.version ++ "-" ++ hash;
};

let rec resolvePackage = (pkgName: string, basedir: Path.t) => {
  let packagePath = (pkgName, basedir) =>
    Path.(basedir / "node_modules" / pkgName);
  let scopedPackagePath = (scope, pkgName, basedir) =>
    Path.(basedir / "node_modules" / scope / pkgName);
  let packagePath =
    switch pkgName.[0] {
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
    if%bind (Io.exists(packagePath)) {
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

let ofDir = (config: Config.t) => {
  open RunAsync.Syntax;
  let resolutionCache = Memoize.create(~size=200);
  let resolvePackageCached = (pkgName, basedir) => {
    let key = (pkgName, basedir);
    let compute = () => resolvePackage(pkgName, basedir);
    resolutionCache(key, compute);
  };
  let packageCache = Memoize.create(~size=200);
  let rec loadPackage = (path: Path.t) => {
    let addDeps =
        (~skipUnresolved=false, ~make, dependencies, prevDependencies) => {
      let resolve = (pkgName: string) =>
        switch%lwt (resolvePackageCached(pkgName, path)) {
        | Ok(Some(depPackagePath)) =>
          switch%lwt (loadPackageCached(depPackagePath)) {
          | Ok(pkg) => Lwt.return_ok((pkgName, Some(pkg)))
          | Error(err) => Lwt.return_error((pkgName, Run.formatError(err)))
          }
        | Ok(None) => Lwt.return_ok((pkgName, None))
        | Error(err) => Lwt.return_error((pkgName, Run.formatError(err)))
        };
      let%lwt dependencies =
        StringMap.bindings(dependencies)
        |> Lwt_list.map_p(((pkgName, _)) => resolve(pkgName));
      let f = dependencies =>
        fun
        | Ok((_, Some(pkg))) => [make(pkg), ...dependencies]
        | Ok((pkgName, None)) =>
          if (skipUnresolved) {
            dependencies;
          } else {
            [
              Package.InvalidDependency({
                pkgName,
                reason: "unable to resolve package"
              }),
              ...dependencies
            ];
          }
        | Error((pkgName, reason)) => [
            Package.InvalidDependency({pkgName, reason}),
            ...dependencies
          ];
      Lwt.return(
        ListLabels.fold_left(~f, ~init=prevDependencies, dependencies)
      );
    };
    switch%bind (Package.Manifest.ofDir(path)) {
    | Some(manifest) =>
      let dependencies = [];
      let%lwt dependencies =
        addDeps(
          ~make=pkg => Package.Dependency(pkg),
          manifest.Package.Manifest.dependencies,
          dependencies
        );
      let%lwt dependencies =
        addDeps(
          ~make=pkg => Package.PeerDependency(pkg),
          manifest.peerDependencies,
          dependencies
        );
      let%lwt dependencies =
        addDeps(
          ~skipUnresolved=true,
          ~make=pkg => Package.OptDependency(pkg),
          manifest.optDependencies,
          dependencies
        );
      let%lwt dependencies =
        addDeps(
          ~skipUnresolved=true,
          ~make=pkg => Package.DevDependency(pkg),
          manifest.devDependencies,
          dependencies
        );
      let sourceType = {
        let isRootPath = path == config.sandboxPath;
        let hasDepWithSourceTypeDevelopment =
          List.exists(
            fun
            | Package.Dependency(pkg)
            | Package.PeerDependency(pkg)
            | Package.OptDependency(pkg) =>
              pkg.sourceType == Package.SourceType.Development
            | Package.DevDependency(_)
            | Package.InvalidDependency(_) => false,
            dependencies
          );
        switch (
          isRootPath,
          hasDepWithSourceTypeDevelopment,
          manifest._resolved
        ) {
        | (true, _, _) => Package.SourceType.Root
        | (_, true, _) => Package.SourceType.Development
        | (_, _, None) => Package.SourceType.Development
        | (_, _, Some(_)) => Package.SourceType.Immutable
        };
      };
      let id = packageId(manifest, dependencies);
      let%bind sourcePath = {
        let linkPath = Path.(path / "_esylink");
        if%bind (Io.exists(linkPath)) {
          let%bind path = Io.readFile(linkPath);
          path
          |> String.trim
          |> Path.of_string
          |> Run.liftOfBosError
          |> RunAsync.liftOfRun;
        } else {
          return(path);
        };
      };
      let pkg =
        Package.{
          id,
          name: manifest.name,
          version: manifest.version,
          dependencies,
          buildCommands: manifest.esy.build,
          installCommands: manifest.esy.install,
          buildType: manifest.esy.buildsInSource,
          sourceType,
          exportedEnv: manifest.esy.exportedEnv,
          sourcePath: ConfigPath.ofPath(config, sourcePath)
        };
      return(pkg);
    | None => error("unable to find manifest")
    };
  }
  and loadPackageCached = (path: Path.t) => {
    let compute = () => loadPackage(path);
    packageCache(path, compute);
  };
  let%bind root = loadPackageCached(config.sandboxPath);
  return({root: root});
};
