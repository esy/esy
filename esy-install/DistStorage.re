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
  | Empty(list(Path.t))
  /* cached source path which could be safely removed */
  | Path(Path.t)
  /* source path from some local package, should be retained */
  | SourcePath(Path.t)
  /* downloaded tarball */
  | Tarball({
      tarballPath: Path.t,
      stripComponents: int,
    });

let esyChecksumKind = kind =>
  switch (kind) {
  | `MD5 => Checksum.Md5
  | `SHA256 => Checksum.Sha256
  | `SHA512 => Checksum.Sha512
  };

let cache = (fetched, tarballPath) =>
  RunAsync.Syntax.(
    switch (fetched) {
    | Empty(_) =>
      let%bind unpackPath = Fs.randomPathVariation(tarballPath);
      let%bind tempTarballPath = Fs.randomPathVariation(tarballPath);
      let%bind () = Fs.createDir(unpackPath);
      let%bind () = Tarball.create(~filename=tempTarballPath, unpackPath);
      let%bind () =
        Fs.rename(~skipIfExists=true, ~src=tempTarballPath, tarballPath);
      let%bind () = Fs.rmPath(unpackPath);
      return(Tarball({tarballPath, stripComponents: 0}));
    | SourcePath(path) =>
      let%bind tempTarballPath = Fs.randomPathVariation(tarballPath);
      let%bind () = Tarball.create(~filename=tempTarballPath, path);
      let%bind () =
        Fs.rename(~skipIfExists=true, ~src=tempTarballPath, tarballPath);
      return(Tarball({tarballPath, stripComponents: 0}));
    | Path(path) =>
      let%bind tempTarballPath = Fs.randomPathVariation(tarballPath);
      let%bind () = Tarball.create(~filename=tempTarballPath, path);
      let%bind () =
        Fs.rename(~skipIfExists=true, ~src=tempTarballPath, tarballPath);
      let%bind () = Fs.rmPath(path);
      return(Tarball({tarballPath, stripComponents: 0}));
    | Tarball(info) =>
      let%bind tempTarballPath = Fs.randomPathVariation(tarballPath);
      let%bind unpackPath = Fs.randomPathVariation(info.tarballPath);
      let%bind () =
        Tarball.unpack(~stripComponents=1, ~dst=unpackPath, info.tarballPath);
      let%bind () = Tarball.create(~filename=tempTarballPath, unpackPath);
      let%bind () =
        Fs.rename(~skipIfExists=true, ~src=tempTarballPath, tarballPath);
      let%bind () = Fs.rmPath(info.tarballPath);
      let%bind () = Fs.rmPath(unpackPath);
      return(Tarball({tarballPath, stripComponents: 0}));
    }
  );

let ofCachedTarball = path =>
  Tarball({tarballPath: path, stripComponents: 0});
let ofDir = path => SourcePath(path);

let fetch' = (sandbox, dist, pkg, gitUsername, gitPassword) => {
  open RunAsync.Syntax;
  let tempPath = SandboxSpec.tempPath(sandbox);
  switch (dist) {
  | Dist.LocalPath({path: srcPath, manifest: _}) =>
    let%lwt () = Logs_lwt.app(m => m("LocalPath: blahhhh"));
    let srcPath = DistPath.toPath(sandbox.SandboxSpec.path, srcPath);
    return(SourcePath(srcPath));

  | Dist.NoSource =>
    let __path = CachePaths.fetchedDist(sandbox, dist);
    switch (pkg) {
    | Some(pkg) =>
      let extraSources = Package.extraSources(pkg);
      let%bind () = Fs.createDir(__path);
      let%lwt extraSourcePaths =
        Lwt_list.fold_left_s(
          (acc, {ExtraSource.url, checksum, relativePath}) => {
            let tarballPath = Path.(__path / relativePath);
            let%lwt () =
              Logs_lwt.app(m =>
                m("tarball Path: %s", Fpath.to_string(tarballPath))
              );

            Curl.download(~output=tarballPath, url) |> ignore;
            // TODO: integrity check
            // Checksum.checkFile(
            //   ~path=tarballPath,
            //   (esyChecksumKind(checksumKind), checksumContents),
            // )
            // |> ignore;
            Lwt.return(List.cons(tarballPath, acc));
          },
          [],
          extraSources,
        );

      return(Empty(extraSourcePaths));
    | None => return(Empty([]))
    };

  | Dist.Archive({url, checksum}) =>
    let path = CachePaths.fetchedDist(sandbox, dist);
    let%lwt () = Logs_lwt.app(m => m("Archive: blahhhh %s", url));
    Fs.withTempDir(
      ~tempPath,
      stagePath => {
        let%bind () = Fs.createDir(stagePath);
        let tarballPath = Path.(stagePath / "archive");
        let%bind () = Curl.download(~output=tarballPath, url);
        let%bind () = Checksum.checkFile(~path=tarballPath, checksum);
        let%bind () = Fs.createDir(Path.parent(path));
        let%bind () = Fs.rename(~skipIfExists=true, ~src=tarballPath, path);
        return(Tarball({tarballPath: path, stripComponents: 1}));
      },
    );

  | Dist.Github(github) =>
    let%lwt () = Logs_lwt.app(m => m("GitHub: blahhhh"));
    let path = CachePaths.fetchedDist(sandbox, dist);
    let%bind () = Fs.createDir(Path.parent(path));
    Fs.withTempDir(
      ~tempPath,
      stagePath => {
        let%bind () = Fs.createDir(stagePath);
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
        let%bind () =
          if (String.length(github.commit) == 40) {
            let%bind () =
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
        let%bind () = Git.checkout(~ref=github.commit, ~repo=stagePath, ());
        let%bind () = Git.updateSubmodules(~config, ~repo=stagePath, ());
        let%bind () = Fs.rename(~skipIfExists=true, ~src=stagePath, path);
        let%bind () =
          switch (github.manifest) {
          | Some((Opam, opamfile)) =>
            let%bind opamContents = Fs.readFile(Path.(path / opamfile));
            let opam =
              OpamFile.OPAM.read(
                OpamFile.make(OpamFilename.of_string(opamfile)),
              );
            let extraSources = OpamFile.OPAM.extra_sources(opam);

            Lwt_list.iter_s(
              ((basename, u)) => {
                let finalfilename = OpamFilename.Base.to_string(basename);
                let url = OpamUrl.to_string(OpamFile.URL.url(u));
                let checksum = OpamFile.URL.checksum(u) |> List.hd;
                let checksumKind = checksum |> OpamHash.kind;
                let checksumContents = checksum |> OpamHash.contents;
                let tarballPath = Path.(path / finalfilename);
                Curl.download(~output=tarballPath, url) |> ignore;
                Checksum.checkFile(
                  ~path=tarballPath,
                  (esyChecksumKind(checksumKind), checksumContents),
                )
                |> ignore;
                Lwt.return();
              },
              extraSources,
            )
            |> ignore;
            return();
          | _ => return()
          };
        let%lwt () =
          Logs_lwt.app(m => m("GitHub: %s", Fpath.to_string(path)));
        return(Path(path));
      },
    );

  | Dist.Git(git) =>
    let%lwt () = Logs_lwt.app(m => m("Git: blahhhh"));
    let path = CachePaths.fetchedDist(sandbox, dist);
    let%bind () = Fs.createDir(Path.parent(path));
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
        let%bind () = Fs.createDir(stagePath);
        let%bind () =
          Git.clone(~config, ~dst=stagePath, ~remote=git.remote, ());
        let%bind () = Git.checkout(~ref=git.commit, ~repo=stagePath, ());
        let%bind () = Git.updateSubmodules(~config, ~repo=stagePath, ());
        let%bind () = Fs.rename(~skipIfExists=true, ~src=stagePath, path);
        let%bind () =
          switch (git.manifest) {
          | Some((Opam, opamfile)) =>
            let%bind opamContents = Fs.readFile(Path.(path / opamfile));
            let opam =
              OpamFile.OPAM.read(
                OpamFile.make(OpamFilename.of_string(opamfile)),
              );
            let extraSources = OpamFile.OPAM.extra_sources(opam);

            Lwt_list.iter_s(
              ((basename, u)) => {
                let finalfilename = OpamFilename.Base.to_string(basename);
                let url = OpamUrl.to_string(OpamFile.URL.url(u));
                let checksum = OpamFile.URL.checksum(u) |> List.hd;
                let checksumKind = checksum |> OpamHash.kind;
                let checksumContents = checksum |> OpamHash.contents;
                let tarballPath = Path.(path / finalfilename);
                Curl.download(~output=tarballPath, url) |> ignore;
                Checksum.checkFile(
                  ~path=tarballPath,
                  (esyChecksumKind(checksumKind), checksumContents),
                )
                |> ignore;
                Lwt.return();
              },
              extraSources,
            )
            |> ignore;
            return();
          | _ => return()
          };
        return(Path(path));
      },
    );
  };
};

let fetch = (_cfg, sandbox, dist, pkg, gitUsername, gitPassword) =>
  RunAsync.contextf(
    fetch'(sandbox, dist, pkg, gitUsername, gitPassword),
    "fetching dist: %a",
    Dist.pp,
    dist,
  );

/* unpack fetched dist into directory */
let unpack = (fetched, path) =>
  RunAsync.Syntax.(
    switch (fetched) {
    | Empty(paths) =>
      Fs.createDir(path) |> ignore;
      Lwt_list.iter_s(
        filepath => {
          let filename = Fpath.basename(filepath);
          let%lwt () = Logs_lwt.app(m => m("filename: %s", filename));
          Fs.copyFile(~src=filepath, ~dst=Path.(path / filename)) |> ignore;
          Lwt.return();
        },
        paths,
      )
      |> ignore;
      return();
    | SourcePath(srcPath)
    | Path(srcPath) =>
      let%bind names = Fs.listDir(srcPath);
      let%lwt () =
        Logs_lwt.app(m =>
          m(
            "names: %s %s",
            String.concat(" ", names),
            Fpath.to_string(path),
          )
        );

      let copy = name => {
        let src = Path.(srcPath / name);
        let dst = Path.(path / name);
        Fs.copyPath(~src, ~dst);
      };

      let%bind () = RunAsync.List.mapAndWait(~f=copy, names);

      return();
    | Tarball({tarballPath, stripComponents}) =>
      Tarball.unpack(~stripComponents, ~dst=path, tarballPath)
    }
  );

let fetchIntoCache = (cfg, sandbox, dist: Dist.t, gitUsername, gitPassword) => {
  open RunAsync.Syntax;
  let path = CachePaths.cachedDist(cfg, dist);
  if%bind (Fs.exists(path)) {
    return(path);
  } else {
    let%bind fetched =
      fetch(cfg, sandbox, dist, None, gitUsername, gitPassword);
    let tempPath = SandboxSpec.tempPath(sandbox);
    Fs.withTempDir(
      ~tempPath,
      stagePath => {
        let%bind () = unpack(fetched, stagePath);
        let%bind () = Fs.rename(~skipIfExists=true, ~src=stagePath, path);
        return(path);
      },
    );
  };
};
