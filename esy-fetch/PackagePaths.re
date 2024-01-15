open EsyPackageConfig;
module String = Astring.String;
let key = pkg => {
  let hash = {
    open Digestv;
    let digest = ofString(PackageId.show(pkg.Package.id));
    // Modify digest if we change how we fetch sources.
    let digest = {
      let version = PackageId.version(pkg.id);
      switch (version) {
      | Source(Dist(Github(_))) => digest |> add(string("2"))
      | Source(Dist(Git(_))) => digest |> add(string("1"))
      | _ => digest
      };
    };
    let digest = Digestv.toHex(digest);
    String.Sub.to_string(String.sub(~start=0, ~stop=8, digest));
  };

  let suffix =
    /* we try to have nice suffix for package with a version */
    switch (pkg.Package.version) {
    | Version.Source(_) => hash
    | Version.Npm(_)
    | Version.Opam(_) => Version.show(pkg.version) ++ "__" ++ hash
    };

  Path.safeSeg(pkg.Package.name ++ "__" ++ suffix);
};

let stagePath = (sandbox, pkg) =>
  Path.(sandbox.Sandbox.cfg.sourceStagePath / key(pkg));

let cachedTarballPath = (sandbox, pkg) =>
  switch (sandbox.Sandbox.cfg.sourceArchivePath, pkg.Package.source) {
  | (None, _) => None
  | (Some(_), Link(_)) =>
    /* has config, not caching b/c it's a link */
    None
  | (Some(sourceArchivePath), Install(_)) =>
    let id = key(pkg);
    Some(Path.(sourceArchivePath /\/ v(id) |> addExt("tgz")));
  };

let installPath = (sandbox, pkg) =>
  switch (pkg.Package.source) {
  | Link({path, manifest: _, kind: _}) =>
    DistPath.toPath(sandbox.Sandbox.spec.path, path)
  | Install(_) => Path.(sandbox.Sandbox.cfg.sourceInstallPath / key(pkg))
  };

let commit = (~needRewrite, stagePath, installPath) =>
  RunAsync.Syntax.
    /* See distStagePath for details */
    (
      {
        let* () =
          if (needRewrite) {
            RewritePrefix.rewritePrefix(
              ~origPrefix=stagePath,
              ~destPrefix=installPath,
              stagePath,
            );
          } else {
            return();
          };

        Fs.rename(~skipIfExists=true, ~src=stagePath, installPath);
      }
    );
