module StringMap = Map.Make(String);

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
  open Sha256;
  let ctx = init();
  update_string(ctx, manifest.name);
  update_string(ctx, manifest.version);
  update_string(ctx, Package.CommandList.show(manifest.esy.build));
  update_string(ctx, Package.CommandList.show(manifest.esy.install));
  update_string(ctx, Package.BuildType.show(manifest.esy.buildsInSource));
  update_string(ctx, manifest._resolved);
  let updateWithDepId =
    fun
    | Package.Dependency(pkg)
    | Package.OptDependency(pkg)
    | Package.PeerDependency(pkg) => update_string(ctx, pkg.id)
    | Package.InvalidDependency(_)
    | Package.DevDependency(_) => ();
  List.iter(updateWithDepId, dependencies);
  let hash = finalize(ctx);
  let hash = String.sub(to_hex(hash), 0, 8);
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

let ofDir = path => {
  open RunAsync.Syntax;
  let resolutionCache = Memoize.create(~size=200);
  let resolvePackageCached = (pkgName, basedir) => {
    let key = (pkgName, basedir);
    let compute = () => resolvePackage(pkgName, basedir);
    resolutionCache(key, compute);
  };
  let packageCache = Memoize.create(~size=200);
  let rec loadPackage = (path: EsyLib.Path.t) => {
    let resolveDep = (pkgName: string) =>
      switch%lwt (resolvePackageCached(pkgName, path)) {
      | Ok(Some(depPackagePath)) =>
        switch%lwt (loadPackageCached(depPackagePath)) {
        | Ok(pkg) => Lwt.return_ok((pkgName, Some(pkg)))
        | Error(err) => Lwt.return_error((pkgName, Run.formatError(err)))
        }
      | Ok(None) => Lwt.return_ok((pkgName, None))
      | Error(err) => Lwt.return_error((pkgName, Run.formatError(err)))
      };
    let addDeps = (~allowFailure=false, dependencies, make, prevDependencies) => {
      let%lwt dependencies =
        StringMap.bindings(dependencies)
        |> List.map(((pkgName, _)) => pkgName)
        |> Lwt_list.map_p(resolveDep);
      let f = dependencies =>
        fun
        | Ok((_, Some(pkg))) => [make(pkg), ...dependencies]
        | Ok((pkgName, None)) =>
          if (allowFailure) {
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
          manifest.Package.Manifest.dependencies,
          pkg => Package.Dependency(pkg),
          dependencies
        );
      let%lwt dependencies =
        addDeps(
          manifest.peerDependencies,
          pkg => Package.PeerDependency(pkg),
          dependencies
        );
      let%lwt dependencies =
        addDeps(
          ~allowFailure=true,
          manifest.optDependencies,
          pkg => Package.OptDependency(pkg),
          dependencies
        );
      let id = packageId(manifest, dependencies);
      let pkg =
        Package.{
          id,
          name: manifest.name,
          version: manifest.version,
          dependencies,
          buildCommands: manifest.esy.build,
          installCommands: manifest.esy.install,
          buildType: manifest.esy.buildsInSource,
          sourceType: SourceType.Immutable,
          exportedEnv: manifest.esy.exportedEnv,
          sourcePath: path
        };
      return(pkg);
    | None => error("unable to find manifest")
    };
  }
  and loadPackageCached = (path: Path.t) => {
    let compute = () => loadPackage(path);
    packageCache(path, compute);
  };
  loadPackageCached(path);
};
