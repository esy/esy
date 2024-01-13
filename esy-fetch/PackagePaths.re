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
  /* We are getting EACCESS error on Windows if we try to rename directory
   * from stage to install after we read a file from there. It seems we are
   * leaking fds and Windows prevent rename from working.
   *
   * For now we are unpacking and running lifecycle directly in a final
   * directory and in case of an error we do a cleanup by removing the
   * install directory (so that subsequent installation attempts try to do
   * install again).
   */
  switch (System.Platform.host) {
  | Windows => Path.(sandbox.Sandbox.cfg.sourceInstallPath / key(pkg))
  | _ => Path.(sandbox.Sandbox.cfg.sourceStagePath / key(pkg))
  };

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
      switch (System.Platform.host) {
      | Windows => RunAsync.return()
      | _ =>
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
