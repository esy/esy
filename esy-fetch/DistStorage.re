open EsyPackageConfig;

module CachePaths = {
  let key = dist => Digest.to_hex(Digest.string(Dist.show(dist)));

  let fetchedDist = (sandbox, dist) =>
    Path.(SandboxSpec.distPath(sandbox) / key(dist));

  let cachedDist = (cfg, dist) =>
    Path.(cfg.Config.sourceFetchPath / key(dist));
};

/* dist which is fetched */
type fetchedDist =
  /* no sources, corresponds to Dist.NoSource */
  | Empty
  /* cached source path which could be safely removed */
  | Path(Path.t)
  /* source path from some local package, should be retained */
  | SourcePath(Path.t)
  /* downloaded tarball */
  | Tarball({
      tarballPath: Path.t,
      stripComponents: int,
    });

let cache = (fetched, tarballPath) =>
  RunAsync.Syntax.(
    switch (fetched) {
    | Empty =>
      let* unpackPath = Fs.randomPathVariation(tarballPath);
      let* tempTarballPath = Fs.randomPathVariation(tarballPath);
      let* () = Fs.createDir(unpackPath);
      let* () = Tarball.create(~filename=tempTarballPath, unpackPath);
      let* () =
        Fs.rename(~skipIfExists=true, ~src=tempTarballPath, tarballPath);
      let* () = Fs.rmPath(unpackPath);
      return(Tarball({tarballPath, stripComponents: 0}));
    | SourcePath(path) =>
      let* tempTarballPath = Fs.randomPathVariation(tarballPath);
      let* () = Tarball.create(~filename=tempTarballPath, path);
      let* () =
        Fs.rename(~skipIfExists=true, ~src=tempTarballPath, tarballPath);
      return(Tarball({tarballPath, stripComponents: 0}));
    | Path(path) =>
      let* tempTarballPath = Fs.randomPathVariation(tarballPath);
      let* () = Tarball.create(~filename=tempTarballPath, path);
      let* () =
        Fs.rename(~skipIfExists=true, ~src=tempTarballPath, tarballPath);
      let* () = Fs.rmPath(path);
      return(Tarball({tarballPath, stripComponents: 0}));
    | Tarball(info) =>
      let* tempTarballPath = Fs.randomPathVariation(tarballPath);
      let* unpackPath = Fs.randomPathVariation(info.tarballPath);
      let* () =
        Tarball.unpack(~stripComponents=1, ~dst=unpackPath, info.tarballPath);
      let* () = Tarball.create(~filename=tempTarballPath, unpackPath);
      let* () =
        Fs.rename(~skipIfExists=true, ~src=tempTarballPath, tarballPath);
      let* () = Fs.rmPath(info.tarballPath);
      let* () = Fs.rmPath(unpackPath);
      return(Tarball({tarballPath, stripComponents: 0}));
    }
  );

let ofCachedTarball = path =>
  Tarball({tarballPath: path, stripComponents: 0});
let ofDir = path => SourcePath(path);

let fetch' = (sandbox, dist, gitUsername, gitPassword, ~extraSources=?, ()) => {
  open RunAsync.Syntax;
  let tempPath = SandboxSpec.tempPath(sandbox);
  switch (dist) {
  | Dist.LocalPath({path: srcPath, manifest: _}) =>
    let srcPath = DistPath.toPath(sandbox.SandboxSpec.path, srcPath);
    return(SourcePath(srcPath));

  | Dist.NoSource =>
    switch (extraSources) {
    | Some(extraSources) =>
      if (extraSources == []) {
        return(Empty);
      } else {
        let path = CachePaths.fetchedDist(sandbox, dist);
        let* () = Fs.createDir(path);
        Fs.withTempDir(
          ~tempPath,
          stagePath => {
            let%bind () = Fs.createDir(stagePath);
            let%bind _ =
              RunAsync.List.map(
                ~f=
                  ({ExtraSource.url, checksum, relativePath}) => {
                    open RunAsync.Syntax;
                    let tarballPath = Path.(stagePath / relativePath);
                    let* _ = Curl.download(~output=tarballPath, url);
                    let* _ = Checksum.checkFile(~path=tarballPath, checksum);
                    let* _ =
                      Fs.rename(
                        ~skipIfExists=true,
                        ~src=tarballPath,
                        Path.(path / relativePath),
                      );
                    RunAsync.return();
                  },
                extraSources,
              );
            return(Path(path));
          },
        );
      }
    | None => return(Empty)
    }

  | Dist.Archive({url, checksum}) =>
    let path = CachePaths.fetchedDist(sandbox, dist);
    Fs.withTempDir(
      ~tempPath,
      stagePath => {
        let* () = Fs.createDir(stagePath);
        let tarballPath = Path.(stagePath / "archive");
        let* () = Curl.download(~output=tarballPath, url);
        let* () = Checksum.checkFile(~path=tarballPath, checksum);
        let* () = Fs.createDir(Path.parent(path));
        let* () = Fs.rename(~skipIfExists=true, ~src=tarballPath, path);
        return(Tarball({tarballPath: path, stripComponents: 1}));
      },
    );

  | Dist.Github(github) =>
    let path = CachePaths.fetchedDist(sandbox, dist);
    let* () = Fs.createDir(Path.parent(path));
    Fs.withTempDir(
      ~tempPath,
      stagePath => {
        let* () = Fs.createDir(stagePath);
        let remote =
          Printf.sprintf(
            "https://github.com/%s/%s.git",
            github.user,
            github.repo,
          );
        let config =
          switch (gitUsername, gitPassword) {
          | (Some(gitUsername), Some(gitPassword)) => [
              (
                "credential.helper",
                Printf.sprintf(
                  "!f() { sleep 1; echo username=%s; echo password=%s; }; f",
                  gitUsername,
                  gitPassword,
                ),
              ),
            ]
          | _ => []
          };
        /* Optimisation: if we find that the commit hash is long, we can shallow clone. */
        let* () =
          if (String.length(github.commit) == 40) {
            let* () =
              Git.clone(~dst=stagePath, ~config, ~remote, ~depth=1, ());
            Git.fetch(
              ~ref=github.commit,
              ~depth=1,
              ~dst=stagePath,
              ~remote,
              (),
            );
          } else {
            Git.clone(~config, ~dst=stagePath, ~remote, ());
          };
        let* () = Git.checkout(~ref=github.commit, ~repo=stagePath, ());
        let* () = Git.updateSubmodules(~config, ~repo=stagePath, ());
        let* () = Fs.rename(~skipIfExists=true, ~src=stagePath, path);
        // TODO: handle extraSouces for Git repos
        return(Path(path));
      },
    );

  | Dist.Git(git) =>
    let path = CachePaths.fetchedDist(sandbox, dist);
    let* () = Fs.createDir(Path.parent(path));
    Fs.withTempDir(
      ~tempPath,
      stagePath => {
        let config =
          switch (gitUsername, gitPassword) {
          | (Some(gitUsername), Some(gitPassword)) => [
              (
                "credential.helper",
                Printf.sprintf(
                  "!f() { sleep 1; echo username=%s; echo password=%s; }; f",
                  gitUsername,
                  gitPassword,
                ),
              ),
            ]
          | _ => []
          };
        let* () = Fs.createDir(stagePath);
        let* () = Git.clone(~config, ~dst=stagePath, ~remote=git.remote, ());
        let* () = Git.checkout(~ref=git.commit, ~repo=stagePath, ());
        let* () = Git.updateSubmodules(~config, ~repo=stagePath, ());
        switch (git.manifest) {
        | Some((_manifestType, manifestFile)) =>
          switch (Path.ofString(Filename.dirname(manifestFile))) {
          | Ok(manifestFilePath) =>
            let packagePath =
              DistPath.toPath(stagePath, DistPath.ofPath(manifestFilePath));
            let* () = Fs.rename(~skipIfExists=true, ~src=packagePath, path);
            // TODO: handle extraSouces for Git repos
            return(Path(path));
          | Error(`Msg(msg)) => errorf("%s", msg)
          }
        | None =>
          let* () = Fs.rename(~skipIfExists=true, ~src=stagePath, path);
          // TODO: handle extraSouces for Git repos
          return(Path(path));
        };
      },
    );
  };
};

let fetch =
    (_cfg, sandbox, dist, gitUsername, gitPassword, ~extraSources=?, ()) =>
  RunAsync.contextf(
    fetch'(sandbox, dist, gitUsername, gitPassword, ~extraSources?, ()),
    "fetching dist: %a",
    Dist.pp,
    dist,
  );

/* unpack fetched dist into directory */
let unpack = (fetched, path) =>
  RunAsync.Syntax.(
    switch (fetched) {
    | Empty => Fs.createDir(path)
    | SourcePath(srcPath)
    | Path(srcPath) =>
      let* names = Fs.listDir(srcPath);
      let copy = name => {
        let src = Path.(srcPath / name);
        let dst = Path.(path / name);
        Fs.copyPath(~src, ~dst);
      };

      let* () = RunAsync.List.mapAndWait(~f=copy, names);

      return();
    | Tarball({tarballPath, stripComponents}) =>
      let%lwt () =
        Esy_logs_lwt.debug(m =>
          m(
            "tarballPath %s, path %s",
            Fpath.to_string(tarballPath),
            Fpath.to_string(path),
          )
        );
      Tarball.unpack(~stripComponents, ~dst=path, tarballPath);
    }
  );

let fetchIntoCache = (cfg, sandbox, dist: Dist.t, gitUsername, gitPassword) => {
  open RunAsync.Syntax;
  let path = CachePaths.cachedDist(cfg, dist);
  if%bind (Fs.exists(path)) {
    return(path);
  } else {
    let* fetched = fetch(cfg, sandbox, dist, gitUsername, gitPassword, ());
    let tempPath = SandboxSpec.tempPath(sandbox);
    Fs.withTempDir(
      ~tempPath,
      stagePath => {
        let* () = unpack(fetched, stagePath);
        let* () = Fs.rename(~skipIfExists=true, ~src=stagePath, path);
        return(path);
      },
    );
  };
};
