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
    | Package.PeerDependency(pkg) => update_string(ctx, pkg.id)
    | Package.InvalidDependency(_)
    | Package.DevDependency(_) => ();
  List.iter(updateWithDepId, dependencies);
  let hash = finalize(ctx);
  let hash = String.sub(to_hex(hash), 0, 8);
  safePackageName(manifest.name) ++ "-" ++ manifest.version ++ "-" ++ hash;
};

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
      let dependencies = dependencies @ peerDependencies;
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
