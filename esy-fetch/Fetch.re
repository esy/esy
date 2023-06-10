open EsyPackageConfig;

module String = Astring.String;

let fetchOverrideFiles = (cfg, sandbox, override: EsyPackageConfig.Override.t) =>
  RunAsync.Syntax.(
    switch (override) {
    | OfJson(_) => return([])
    | OfDist(info) =>
      let* path =
        DistStorage.fetchIntoCache(cfg, sandbox, info.dist, None, None);
      File.ofDir(Path.(path / "files"));
    | OfOpamOverride(info) => File.ofDir(Path.(info.path / "files"))
    }
  );

let fetchOverridesFiles = (cfg, sandbox, overrides) => {
  open RunAsync.Syntax;
  let f = (files, override) => {
    let* filesOfOverride = fetchOverrideFiles(cfg, sandbox, override);
    return(filesOfOverride @ files);
  };

  let fold' = (~f, ~init, overrides) =>
    RunAsync.List.foldLeft(~f, ~init, List.rev(overrides));

  fold'(~f, ~init=[], overrides);
};

module NpmPackageJson: {
  type t;

  type lifecycle = {
    postinstall: option(string),
    install: option(string),
  };

  let ofDir: Path.t => RunAsync.t(option(t));

  let bin: (~sourcePath: Path.t, t) => list((string, Path.t));
  let lifecycle: t => option(lifecycle);
} = {
  module Lifecycle = {
    [@deriving of_yojson({strict: false})]
    type t = {
      postinstall: [@default None] option(string),
      install: [@default None] option(string),
    };
  };

  module Bin = {
    type t =
      | Empty
      | One(string)
      | Many(StringMap.t(string));

    let of_yojson =
      Result.Syntax.(
        fun
        | `String(cmd) => {
            let cmd = String.trim(cmd);
            switch (cmd) {
            | "" => return(Empty)
            | cmd => return(One(cmd))
            };
          }
        | `Assoc(items) => {
            let* items = {
              let f = (cmds, (name, json)) =>
                switch (json) {
                | `String(cmd) => return(StringMap.add(name, cmd, cmds))
                | _ => error("expected a string")
                };

              Result.List.foldLeft(~f, ~init=StringMap.empty, items);
            };

            return(Many(items));
          }
        | _ => error("expected a string or an object")
      );
  };

  [@deriving of_yojson({strict: false})]
  type t = {
    [@default None]
    name: option(string),
    bin: [@default Bin.Empty] Bin.t,
    scripts: [@default None] option(Lifecycle.t),
    esy: [@default None] option(Json.t),
  };

  type lifecycle =
    Lifecycle.t = {
      postinstall: option(string),
      install: option(string),
    };

  let ofDir = path => {
    open RunAsync.Syntax;
    if%bind (Fs.exists(Path.(path / "esy.json"))) {
      return(None);
    } else {
      let filename = Path.(path / "package.json");
      if%bind (Fs.exists(filename)) {
        let* json = Fs.readJsonFile(filename);
        let* manifest = RunAsync.ofRun(Json.parseJsonWith(of_yojson, json));
        if (Option.isSome(manifest.esy)) {
          return(None);
        } else {
          return(Some(manifest));
        };
      } else {
        return(None);
      };
    };
  };

  let bin = (~sourcePath, pkgJson) => {
    let makePathToCmd = cmdPath =>
      Path.(sourcePath /\/ v(cmdPath) |> normalize);
    switch (pkgJson.bin, pkgJson.name) {
    | (Bin.One(cmd), Some(name)) => [(name, makePathToCmd(cmd))]
    | (Bin.One(cmd), None) =>
      let cmd = makePathToCmd(cmd);
      let name = Path.basename(cmd);
      [(name, cmd)];
    | (Bin.Many(cmds), _) =>
      let f = (name, cmd, cmds) => [(name, makePathToCmd(cmd)), ...cmds];
      StringMap.fold(f, cmds, []);
    | (Bin.Empty, _) => []
    };
  };

  let lifecycle = pkgJson =>
    switch (pkgJson.scripts) {
    | Some({Lifecycle.postinstall: None, install: None}) => None
    | lifecycle => lifecycle
    };
};

module PackagePaths = {
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
};

module FetchPackage: {
  type fetch;

  type installation = {
    pkg: Package.t,
    pkgJson: option(NpmPackageJson.t),
    path: Path.t,
  };

  let fetch:
    (Sandbox.t, Package.t, option(string), option(string)) =>
    RunAsync.t(fetch);
  let install:
    (Path.t => RunAsync.t(unit), Sandbox.t, fetch) =>
    RunAsync.t(installation);
} = {
  type fetch = (Package.t, kind)
  and kind =
    | Fetched(DistStorage.fetchedDist)
    | Installed(Path.t)
    | Linked(Path.t);

  type installation = {
    pkg: Package.t,
    pkgJson: option(NpmPackageJson.t),
    path: Path.t,
  };

  /* fetch any of the dists for the package */
  let fetch' = (sandbox, pkg, dists, gitUsername, gitPassword) => {
    open RunAsync.Syntax;

    let rec fetchAny = (errs, alternatives) =>
      switch (alternatives) {
      | [dist, ...rest] =>
        let extraSources = Package.extraSources(pkg);
        let fetched =
          DistStorage.fetch(
            sandbox.Sandbox.cfg,
            sandbox.spec,
            dist,
            ~extraSources,
            gitUsername,
            gitPassword,
            (),
          );
        switch%lwt (fetched) {
        | Ok(fetched) => return(fetched)
        | Error(err) => fetchAny([(dist, err), ...errs], rest)
        };
      | [] =>
        let%lwt () =
          Esy_logs_lwt.err(m => {
            let ppErr = (fmt, (source, err)) =>
              Fmt.pf(
                fmt,
                "source: %a@\nerror: %a",
                Dist.pp,
                source,
                Run.ppError,
                err,
              );

            m(
              "unable to fetch %a:@[<v 2>@\n%a@]",
              Package.pp,
              pkg,
              Fmt.(list(~sep=any("@\n"), ppErr)),
              errs,
            );
          });
        error("installation error");
      };

    fetchAny([], dists);
  };

  let fetch = (sandbox, pkg, gitUsername, gitPassword) =>
    /*** TODO: need to sync here so no two same tasks are running at the same time */
    RunAsync.Syntax.(
      RunAsync.contextf(
        switch (pkg.Package.source) {
        | Link({path, _}) =>
          let path = DistPath.toPath(sandbox.Sandbox.spec.path, path);
          return((pkg, Linked(path)));
        | Install({source: (main, mirrors), opam: _}) =>
          let* cached =
            switch (PackagePaths.cachedTarballPath(sandbox, pkg)) {
            | None => return(None)
            | Some(cachedTarballPath) =>
              if%bind (Fs.exists(cachedTarballPath)) {
                let%lwt () =
                  Esy_logs_lwt.debug(m =>
                    m("fetching %a: found cached tarball", Package.pp, pkg)
                  );
                let dist = DistStorage.ofCachedTarball(cachedTarballPath);
                return(Some((pkg, Fetched(dist))));
              } else {
                let%lwt () =
                  Esy_logs_lwt.debug(m =>
                    m("fetching %a: making cached tarball", Package.pp, pkg)
                  );
                let dists = [main, ...mirrors];
                let* dist =
                  fetch'(sandbox, pkg, dists, gitUsername, gitPassword);
                let* dist = DistStorage.cache(dist, cachedTarballPath);
                return(Some((pkg, Fetched(dist))));
              }
            };

          let path = PackagePaths.installPath(sandbox, pkg);
          if%bind (Fs.exists(path)) {
            let%lwt () =
              Esy_logs_lwt.debug(m =>
                m("fetching %a: installed", Package.pp, pkg)
              );
            return((pkg, Installed(path)));
          } else {
            switch (cached) {
            | Some(cached) => return(cached)
            | None =>
              let%lwt () =
                Esy_logs_lwt.debug(m =>
                  m("fetching %a: fetching", Package.pp, pkg)
                );
              let dists = [main, ...mirrors];
              let* dist =
                fetch'(sandbox, pkg, dists, gitUsername, gitPassword);
              return((pkg, Fetched(dist)));
            };
          };
        },
        "fetching %a",
        Package.pp,
        pkg,
      )
    );

  module Lifecycle = {
    let runScript = (~env=?, ~lifecycleName, pkg, sourcePath, script) => {
      let%lwt () =
        Esy_logs_lwt.app(m =>
          m(
            "%a: running %a lifecycle",
            Package.pp,
            pkg,
            Fmt.(styled(`Bold, string)),
            lifecycleName,
          )
        );

      let readAndCloseFile = path => {
        let%lwt ic = Lwt_io.(open_file(~mode=Input, Path.show(path)));
        Lwt.finalize(() => Lwt_io.read(ic), () => Lwt_io.close(ic));
      };

      /* We don't need to wrap the install path on Windows in quotes */
      try%lwt({
        let installationPath =
          switch (System.Platform.host) {
          | Windows => Path.show(sourcePath)
          | _ => Filename.quote(Path.show(sourcePath))
          };

        /* On Windows, cd by itself won't switch between drives */
        /* We'll add the /d flag to allow switching drives - */
        let changeDirCommand =
          switch (System.Platform.host) {
          | Windows => "/d"
          | _ => ""
          };

        let script =
          Printf.sprintf(
            "cd %s %s && %s",
            changeDirCommand,
            installationPath,
            script,
          );

        let cmd =
          switch (System.Platform.host) {
          | Windows => ("", [|"cmd.exe", "/c " ++ script|])
          | _ => ("/bin/bash", [|"/bin/bash", "-c", script|])
          };

        let env = {
          open Option.Syntax;
          let* env = env;
          let* (_, env) = ChildProcess.prepareEnv(env);
          return(env);
        };

        let logFilePath =
          Path.(sourcePath / "_esy" / (lifecycleName ++ ".log"));
        let%lwt fd =
          Lwt_unix.(
            openfile(Path.show(logFilePath), [O_RDWR, O_CREAT], 0o660)
          );
        let stderrout = `FD_copy(Lwt_unix.unix_file_descr(fd));
        Lwt_process.with_process_out(
          ~env?,
          ~stdout=stderrout,
          ~stderr=stderrout,
          cmd,
          p => {
            let%lwt () = Lwt_unix.close(fd);
            switch%lwt (p#status) {
            | Unix.WEXITED(0) =>
              let%lwt () =
                Esy_logs_lwt.debug(m => m("log at %a", Path.pp, logFilePath));
              RunAsync.return();
            | _ =>
              let%lwt output = readAndCloseFile(logFilePath);
              let%lwt () =
                Esy_logs_lwt.err(m =>
                  m(
                    "@[<v>command failed: %s@\noutput:@[<v 2>@\n%s@]@]",
                    script,
                    output,
                  )
                );
              RunAsync.error("error running command");
            };
          },
        );
      }) {
      | [@implicit_arity] Unix.Unix_error(err, _, _) =>
        let msg = Unix.error_message(err);
        RunAsync.error(msg);
      | _ => RunAsync.error("error running subprocess")
      };
    };

    let run = (pkg, sourcePath, lifecycle) => {
      open RunAsync.Syntax;
      let* env = {
        let path = [
          Path.(show(sourcePath / "_esy")),
          ...System.Environment.path,
        ];
        let sep = System.Environment.sep(~name="PATH", ());
        let override =
          Astring.String.Map.(add("PATH", String.concat(~sep, path), empty));
        return(ChildProcess.CurrentEnvOverride(override));
      };

      let* () =
        switch (lifecycle.NpmPackageJson.install) {
        | Some(cmd) =>
          runScript(~env, ~lifecycleName="install", pkg, sourcePath, cmd)
        | None => return()
        };

      let* () =
        switch (lifecycle.NpmPackageJson.postinstall) {
        | Some(cmd) =>
          runScript(~env, ~lifecycleName="postinstall", pkg, sourcePath, cmd)
        | None => return()
        };

      return();
    };
  };

  let copyFiles = (sandbox, pkg, path) => {
    open RunAsync.Syntax;
    open Package;

    let* filesOfOpam =
      switch (pkg.source) {
      | Link(_)
      | Install({opam: None, _}) => return([])
      | Install({opam: Some(opam), _}) => PackageSource.opamfiles(opam)
      };

    let* filesOfOverride =
      fetchOverridesFiles(
        sandbox.Sandbox.cfg,
        sandbox.Sandbox.spec,
        pkg.Package.overrides,
      );

    RunAsync.List.mapAndWait(
      ~f=File.placeAt(path),
      filesOfOpam @ filesOfOverride,
    );
  };

  let install' = (onBeforeLifecycle, sandbox, pkg, fetched) => {
    open RunAsync.Syntax;

    let installPath = PackagePaths.installPath(sandbox, pkg);

    let* stagePath = {
      let path = PackagePaths.stagePath(sandbox, pkg);
      let* () = Fs.rmPath(path);
      return(path);
    };

    let* () = {
      let%lwt () =
        Esy_logs_lwt.debug(m => m("unpacking %a", Package.pp, pkg));
      RunAsync.contextf(
        DistStorage.unpack(fetched, stagePath),
        "unpacking %a",
        Package.pp,
        pkg,
      );
    };

    let* () = copyFiles(sandbox, pkg, stagePath);
    let* pkgJson = NpmPackageJson.ofDir(stagePath);

    let* () =
      switch (Option.bind(~f=NpmPackageJson.lifecycle, pkgJson)) {
      | Some(lifecycle) =>
        let* () = onBeforeLifecycle(stagePath);
        let* () = Lifecycle.run(pkg, stagePath, lifecycle);
        let* () =
          PackagePaths.commit(~needRewrite=true, stagePath, installPath);
        return();
      | None =>
        let* () =
          PackagePaths.commit(~needRewrite=false, stagePath, installPath);
        return();
      };

    return({pkg, path: installPath, pkgJson});
  };

  let install = (onBeforeLifecycle, sandbox, (pkg, fetch)) =>
    RunAsync.Syntax.(
      RunAsync.contextf(
        switch (fetch) {
        | Linked(path)
        | Installed(path) =>
          let* pkgJson = NpmPackageJson.ofDir(path);
          return({pkg, path, pkgJson});
        | Fetched(fetched) =>
          install'(onBeforeLifecycle, sandbox, pkg, fetched)
        },
        "installing %a",
        Package.pp,
        pkg,
      )
    );
};

module LinkBin = {
  let installNodeBinWrapper = (binPath, (name, origPath)) => {
    let (data, path) =
      switch (System.Platform.host) {
      | Windows =>
        let data =
          Format.asprintf(
            {|@ECHO off
  @SETLOCAL
  node "%a" %%*
            |},
            Path.pp,
            origPath,
          );
        let path = Path.(binPath / name |> addExt(".cmd"));
        (data, path);
      | _ =>
        let data =
          Format.asprintf(
            {|#!/bin/sh
  exec node "%a" "$@"
              |},
            Path.pp,
            origPath,
          );

        let path = Path.(binPath / name);
        (data, path);
      };

    Fs.writeFile(~perm=0o755, ~data, path);
  };

  let installBinWrapperAsBatch = (binPath, (name, origPath)) => {
    let data =
      Fmt.str({|@ECHO off
@SETLOCAL
"%a" %%*
          |}, Path.pp, origPath);

    Fs.writeFile(
      ~perm=0o755,
      ~data,
      Path.(binPath / name |> addExt(".cmd")),
    );
  };

  let installBinWrapperAsSymlink = (binPath, (name, origPath)) => {
    open RunAsync.Syntax;
    let* () = Fs.chmod(0o777, origPath);
    let destPath = Path.(binPath / name);
    if%bind (Fs.exists(destPath)) {
      let* () = Fs.unlink(destPath);
      Fs.symlink(~force=true, ~src=origPath, destPath);
    } else {
      Fs.symlink(~force=true, ~src=origPath, destPath);
    };
  };

  let installBinWrapper = (binPath, (name, origPath)) => {
    open RunAsync.Syntax;
    let%lwt () =
      Esy_logs_lwt.debug(m =>
        m(
          "Fetch:installBinWrapper: %a / %s -> %a",
          Path.pp,
          origPath,
          name,
          Path.pp,
          binPath,
        )
      );
    if%bind (Fs.exists(origPath)) {
      if (Path.hasExt(".js", origPath)) {
        installNodeBinWrapper(binPath, (name, origPath));
      } else {
        switch (System.Platform.host) {
        | Windows => installBinWrapperAsBatch(binPath, (name, origPath))
        | _ => installBinWrapperAsSymlink(binPath, (name, origPath))
        };
      };
    } else {
      let%lwt () =
        Esy_logs_lwt.warn(m =>
          m("missing %a defined as binary", Path.pp, origPath)
        );
      return();
    };
  };

  let link = (binPath, installation) =>
    RunAsync.Syntax.(
      switch (installation.FetchPackage.pkgJson) {
      | Some(pkgJson) =>
        let bin = NpmPackageJson.bin(~sourcePath=installation.path, pkgJson);
        let* () =
          RunAsync.List.mapAndWait(~f=installBinWrapper(binPath), bin);
        return(bin);
      | None => RunAsync.return([])
      }
    );
};

let collectPackagesOfSolution = (fetchDepsSubset, solution) => {
  let (pkgs, root) = {
    let root = Solution.root(solution);

    let rec collect = ((seen, topo), pkg) =>
      if (Package.Set.mem(pkg, seen)) {
        (seen, topo);
      } else {
        let seen = Package.Set.add(pkg, seen);
        let (seen, topo) = collectDependencies((seen, topo), pkg);
        let topo = [pkg, ...topo];
        (seen, topo);
      }
    and collectDependencies = ((seen, topo), pkg) => {
      let dependencies =
        Solution.dependenciesBySpec(solution, fetchDepsSubset, pkg);
      List.fold_left(~f=collect, ~init=(seen, topo), dependencies);
    };

    let (_, topo) = collectDependencies((Package.Set.empty, []), root);
    (List.rev(topo), root);
  };

  (pkgs, root);
};

/** This installs pnp enabled node wrapper. */

let installNodeWrapper = (~binPath, ~pnpJsPath, ()) =>
  RunAsync.Syntax.(
    switch (Cmd.resolveCmd(System.Environment.path, "node")) {
    | Ok(nodeCmd) =>
      let* binPath = {
        let* () = Fs.createDir(binPath);
        return(binPath);
      };

      let* nodeCmd = Fs.realpath(Path.v(nodeCmd));
      let nodeCmd = Path.show(nodeCmd);

      let* () =
        switch (System.Platform.host) {
        | Windows =>
          let data =
            Format.asprintf(
              {|@ECHO off
@SETLOCAL
@SET ESY__NODE_BIN_PATH=%%%a%%
"%s" -r "%a" %%*
            |},
              Path.pp,
              binPath,
              nodeCmd,
              Path.pp,
              pnpJsPath,
            );

          let path = Path.(binPath / "node.cmd");
          Fs.writeFile(~perm=0o755, ~data, path);
        | _ => RunAsync.return()
        };

      let normalizer = Sys.unix ? (x => x) : EsyBash.normalizePathForCygwin;
      let data =
        Format.asprintf(
          {|#!/bin/sh
export ESY__NODE_BIN_PATH='%a'
exec '%s' -r '%a' "$@"
              |},
          Path.pp,
          binPath,
          normalizer(nodeCmd),
          Path.pp,
          pnpJsPath,
        );

      let path = Path.(binPath / "node");
      Fs.writeFile(~perm=0o755, ~data, path);
    | Error(_) =>
      /* no node available in $PATH, just skip this then */
      return()
    }
  );

let isInstalledWithInstallation =
    (fetchDepsSubset, sandbox: Sandbox.t, solution: Solution.t, installation) => {
  open RunAsync.Syntax;
  let rec checkSourcePaths =
    fun
    | [] => return(true)
    | [pkg, ...pkgs] =>
      switch (Installation.find(pkg.Package.id, installation)) {
      | None => return(false)
      | Some(path) =>
        if%bind (Fs.exists(path)) {
          checkSourcePaths(pkgs);
        } else {
          return(false);
        }
      };

  let rec checkCachedTarballPaths =
    fun
    | [] => return(true)
    | [pkg, ...pkgs] =>
      switch (PackagePaths.cachedTarballPath(sandbox, pkg)) {
      | None => checkCachedTarballPaths(pkgs)
      | Some(cachedTarballPath) =>
        if%bind (Fs.exists(cachedTarballPath)) {
          checkCachedTarballPaths(pkgs);
        } else {
          return(false);
        }
      };

  let rec checkInstallationEntry =
    fun
    | [] => true
    | [(pkgid, _path), ...rest] =>
      if (Solution.mem(solution, pkgid)) {
        checkInstallationEntry(rest);
      } else {
        false;
      };

  let (pkgs, _root) = collectPackagesOfSolution(fetchDepsSubset, solution);
  if%bind (checkSourcePaths(pkgs)) {
    if%bind (checkCachedTarballPaths(pkgs)) {
      return(checkInstallationEntry(Installation.entries(installation)));
    } else {
      return(false);
    };
  } else {
    return(false);
  };
};

let maybeInstallationOfSolution =
    (fetchDepsSubset, sandbox: Sandbox.t, solution: Solution.t) => {
  open RunAsync.Syntax;
  let installationPath = SandboxSpec.installationPath(sandbox.spec);
  switch%lwt (Installation.ofPath(installationPath)) {
  | Error(_)
  | Ok(None) => return(None)
  | Ok(Some(installation)) =>
    if%bind (isInstalledWithInstallation(
               fetchDepsSubset,
               sandbox,
               solution,
               installation,
             )) {
      return(Some(installation));
    } else {
      return(None);
    }
  };
};

let fetchPackages =
    (fetchDepsSubset, sandbox, solution, gitUsername, gitPassword) => {
  open RunAsync.Syntax;

  /* Collect packages which from the solution */
  let (pkgs, _root) = collectPackagesOfSolution(fetchDepsSubset, solution);

  let (report, finish) = Cli.createProgressReporter(~name="fetching", ());
  let* items = {
    let f = pkg => {
      let%lwt () = report("%a", Package.pp, pkg);
      let* fetch = FetchPackage.fetch(sandbox, pkg, gitUsername, gitPassword);
      return((pkg, fetch));
    };

    let fetchConcurrency =
      Option.orDefault(~default=40, sandbox.Sandbox.cfg.fetchConcurrency);

    let* items =
      RunAsync.List.mapAndJoin(~concurrency=fetchConcurrency, ~f, pkgs);
    let%lwt () = finish();
    return(items);
  };

  let fetched = {
    let f = (map, (pkg, fetch)) => Package.Map.add(pkg, fetch, map);

    List.fold_left(~f, ~init=Package.Map.empty, items);
  };

  return(fetched);
};

let fetch = (fetchDepsSubset, sandbox, solution, gitUsername, gitPassword) => {
  open RunAsync.Syntax;

  /* Collect packages which from the solution */
  let (pkgs, root) = collectPackagesOfSolution(fetchDepsSubset, solution);

  /* Fetch all packages. */
  let* fetched =
    fetchPackages(
      fetchDepsSubset,
      sandbox,
      solution,
      gitUsername,
      gitPassword,
    );

  /* Produce _esy/<sandbox>/installation.json */
  let* installation = {
    let installation = {
      let f = (installation, pkg) => {
        let id = pkg.Package.id;
        let path = PackagePaths.installPath(sandbox, pkg);
        Installation.add(id, path, installation);
      };

      let init =
        Installation.empty
        |> Installation.add(root.Package.id, sandbox.spec.path);

      List.fold_left(~f, ~init, pkgs);
    };

    let* () =
      Fs.writeJsonFile(
        ~json=Installation.to_yojson(installation),
        SandboxSpec.installationPath(sandbox.spec),
      );

    return(installation);
  };

  /* Install all packages. */
  let* () = {
    let (report, finish) =
      Cli.createProgressReporter(~name="installing", ());
    let queue = LwtTaskQueue.create(~concurrency=40, ());

    let tasks = Memoize.make();

    let install = (pkg, dependencies) => {
      open RunAsync.Syntax;
      let f = () => {
        let id = pkg.Package.id;

        let onBeforeLifecycle = path => {
          /*
           * This creates <install>/_esy and populates it with a custom
           * per-package pnp.js (which allows to resolve dependencies out of
           * stage directory and a node wrapper which uses this pnp.js.
           */
          let binPath = Path.(path / "_esy");
          let* () = Fs.createDir(binPath);

          let* () = {
            let f = dep => {
              let* _: list((string, Path.t)) = LinkBin.link(binPath, dep);
              return();
            };

            RunAsync.List.mapAndWait(~f, dependencies);
          };

          let* () =
            if (pkg.installConfig.pnp == true) {
              let* () = {
                let pnpJsPath = Path.(binPath / "pnp.js");
                let installation = Installation.add(id, path, installation);
                let data =
                  PnpJs.render(
                    ~basePath=binPath,
                    ~rootPath=path,
                    ~rootId=id,
                    ~solution,
                    ~installation,
                    (),
                  );

                let* () = Fs.writeFile(~perm=0o755, ~data, pnpJsPath);
                installNodeWrapper(~binPath, ~pnpJsPath, ());
              };

              return();
            } else {
              return();
            };

          return();
        };

        let fetched = Package.Map.find(pkg, fetched);
        FetchPackage.install(onBeforeLifecycle, sandbox, fetched);
      };

      LwtTaskQueue.submit(queue, f);
    };

    let rec visit' = (seen, pkg) => {
      let* dependencies =
        RunAsync.List.mapAndJoin(
          ~f=visit(seen),
          Solution.dependenciesBySpec(solution, fetchDepsSubset, pkg),
        );

      let%lwt () = report("%a", PackageId.pp, pkg.Package.id);
      install(pkg, List.filterNone(dependencies));
    }
    and visit = (seen, pkg) => {
      let id = pkg.Package.id;
      if (!PackageId.Set.mem(id, seen)) {
        let seen = PackageId.Set.add(id, seen);
        let* installation =
          Memoize.compute(tasks, id, () => visit'(seen, pkg));
        return(Some(installation));
      } else {
        return(None);
      };
    };

    let* rootDependencies =
      RunAsync.List.mapAndJoin(
        ~f=visit(PackageId.Set.empty),
        Solution.dependenciesBySpec(solution, fetchDepsSubset, root),
      );

    let* () = {
      let binPath = SandboxSpec.binPath(sandbox.spec);
      let* () = Fs.createDir(binPath);

      let* _ = {
        let f = (seen, dep) => {
          let* bins = LinkBin.link(binPath, dep);
          let f = (seen, (name, _)) =>
            switch (StringMap.find_opt(name, seen)) {
            | None => StringMap.add(name, [dep.FetchPackage.pkg], seen)
            | Some(pkgs) =>
              let pkgs = [dep.FetchPackage.pkg, ...pkgs];
              Esy_logs.warn(m =>
                m(
                  "executable '%s' is installed by several packages: @[<h>%a@]@;",
                  name,
                  Fmt.(list(~sep=any(", "), Package.pp)),
                  pkgs,
                )
              );
              StringMap.add(name, pkgs, seen);
            };

          return(List.fold_left(~f, ~init=seen, bins));
        };

        RunAsync.List.foldLeft(
          ~f,
          ~init=StringMap.empty,
          List.filterNone(rootDependencies),
        );
      };

      return();
    };

    let%lwt () = finish();
    return();
  };

  let* () =
    if (root.installConfig.pnp) {
      /* Produce _esy/<sandbox>/pnp.js */
      let* () = {
        let path = SandboxSpec.pnpJsPath(sandbox.Sandbox.spec);
        let data =
          PnpJs.render(
            ~basePath=Path.parent(SandboxSpec.pnpJsPath(sandbox.spec)),
            ~rootPath=sandbox.spec.path,
            ~rootId=Solution.root(solution).Package.id,
            ~solution,
            ~installation,
            (),
          );

        Fs.writeFile(~data, path);
      };

      /* place <binPath>/node executable with pnp enabled */
      let* () =
        installNodeWrapper(
          ~binPath=SandboxSpec.binPath(sandbox.Sandbox.spec),
          ~pnpJsPath=SandboxSpec.pnpJsPath(sandbox.spec),
          (),
        );

      return();
    } else {
      return();
    };

  let* () = Fs.rmPath(SandboxSpec.distPath(sandbox.Sandbox.spec));

  return();
};
