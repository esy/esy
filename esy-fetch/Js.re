open RunAsync.Syntax;
open EsyPackageConfig;

type installation = {
  // it's useful to cache the package.json, if a package contains one.
  // We parse package.json before we run the lifecycle hooks, which we
  // do after download the sources of a package as a part of following
  // NPM behaviour.
  pkgJson: option(NpmPackageJson.t),
  pkg: Package.t,
};

/**

   Removes the NPM scope from a package name.
   When NPM packages are installed, binaries are copied
   to the destination without their namespace. This causes
   conflicts but is the expected behaviour.

 */
let skipNPMScope = pkgName => {
  switch (String.split_on_char('/', pkgName)) {
  | [] =>
    failwith(
      "Internal error: String.split_on_char returns a non-empty list usually, but it didn't for: "
      ++ pkgName,
    )
  | x => List.nth(x, List.length(x) - 1)
  };
};

module LinkBin: {
  /**

     Creates node wrapper binaries (shell scripts with shebangs like
     #!/usr/bin/env node ...) in the specified destination path.

     To create wrapper binaries in [destBinWrapperDir], it needs the
     path, [srcPackageDir] to be embedded in the wrapper
     script. [srcPackageDir] doesn't necessarily have to be from
     cache. When pnp = false, [srcPackageDir] points to a path inside
     [node_modules].

  */
  let link:
    (
      ~srcPackageDir: Path.t,
      ~destBinWrapperDir: Path.t,
      ~pkgJson: NpmPackageJson.t
    ) =>
    RunAsync.t(list((string, Path.t)));
} = {
  let installNodeBinWrapper = (destBinWrapperDir, (name, origPath)) => {
    let (data, binWrapperPath) =
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
        let path =
          Path.(destBinWrapperDir / skipNPMScope(name) |> addExt(".cmd"));
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

        let path = Path.(destBinWrapperDir / skipNPMScope(name));
        (data, path);
      };

    Fs.writeFile(~perm=0o755, ~data, binWrapperPath);
  };

  let installBinWrapperAsBatch = (destBinWrapperDir, (name, origPath)) => {
    let data =
      Fmt.str({|@ECHO off
@SETLOCAL
"%a" %%*
          |}, Path.pp, origPath);

    Fs.writeFile(
      ~perm=0o755,
      ~data,
      Path.(destBinWrapperDir / name |> addExt(".cmd")),
    );
  };

  let installBinWrapperAsSymlink = (destBinWrapperDir, (name, origPath)) => {
    open RunAsync.Syntax;
    let* () = Fs.chmod(0o777, origPath);
    let destPath = Path.(destBinWrapperDir / name);
    if%bind (Fs.exists(destPath)) {
      let* () = Fs.unlink(destPath);
      Fs.symlink(~force=true, ~src=origPath, destPath);
    } else {
      Fs.symlink(~force=true, ~src=origPath, destPath);
    };
  };

  let installBinWrapper = (destBinWrapperDir, (name, origPath)) => {
    open RunAsync.Syntax;
    let%lwt () =
      Esy_logs_lwt.debug(m =>
        m(
          "Fetch:installBinWrapper: %a / %s -> %a",
          Path.pp,
          origPath,
          name,
          Path.pp,
          destBinWrapperDir,
        )
      );
    if%bind (Fs.exists(origPath)) {
      if (Path.hasExt(".js", origPath)) {
        installNodeBinWrapper(destBinWrapperDir, (name, origPath));
      } else {
        switch (System.Platform.host) {
        | Windows =>
          installBinWrapperAsBatch(destBinWrapperDir, (name, origPath))
        | _ =>
          installBinWrapperAsSymlink(destBinWrapperDir, (name, origPath))
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

  let link = (~srcPackageDir, ~destBinWrapperDir, ~pkgJson) => {
    open RunAsync.Syntax;
    let makePathToCmd = ((cmd, cmdPath)) => {
      let cmdPath = Path.(srcPackageDir /\/ v(cmdPath) |> normalize);
      (cmd, cmdPath);
    };
    let bins = NpmPackageJson.bin(pkgJson) |> List.map(~f=makePathToCmd);
    let* () =
      RunAsync.List.mapAndWait(
        ~f=installBinWrapper(destBinWrapperDir),
        bins,
      );
    return(bins);
  };
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

      let logFilePath = Path.(sourcePath / "_esy" / (lifecycleName ++ ".log"));
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
        Astring.String.Map.(
          add("PATH", Astring.String.concat(~sep, path), empty)
        );
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

/**

   - Creates pnp.js for JS packages and a node wrapper that uses it to
     resolve require()

   [fetched] is a map of packages
   TODO explain parameters
 */
let install =
    (
      ~sandbox,
      ~dependencies,
      ~solution,
      ~installation,
      ~fetchedKindMap,
      ~queue,
      pkg,
    ) => {
  open RunAsync.Syntax;
  let f = () => {
    let id = pkg.Package.id;

    let onBeforeLifecycle = stagePath => {
      /*
       * This creates <install>/_esy and populates it with a custom
       * per-package pnp.js (which allows to resolve dependencies out of
       * stage directory and a node wrapper which uses this pnp.js.
       */
      let destBinWrapperDir = Path.(stagePath / "_esy");
      let* () = Fs.createDir(destBinWrapperDir);

      let* () = {
        let f = ({pkgJson, pkg}) => {
          let* _: list((string, Path.t)) =
            switch (pkgJson) {
            | Some(pkgJson) =>
              let installPath = PackagePaths.installPath(sandbox, pkg);
              LinkBin.link(
                ~srcPackageDir=installPath,
                ~destBinWrapperDir,
                ~pkgJson,
              );
            | None => RunAsync.return([])
            };
          return();
        };

        RunAsync.List.mapAndWait(~f, dependencies);
      };

      let* () =
        if (pkg.installConfig.pnp == true) {
          let* () = {
            let pnpJsPath = Path.(destBinWrapperDir / "pnp.js");
            let installation = Installation.add(id, stagePath, installation);
            let data =
              PnpJs.render(
                ~basePath=destBinWrapperDir,
                ~rootPath=stagePath,
                ~rootId=id,
                ~solution,
                ~installation,
                (),
              );

            let* () = Fs.writeFile(~perm=0o755, ~data, pnpJsPath);
            installNodeWrapper(~binPath=destBinWrapperDir, ~pnpJsPath, ());
          };

          return();
        } else {
          return();
        };

      return();
    };

    let fetchedKind = Package.Map.find(pkg, fetchedKindMap);
    let stagePath = PackagePaths.stagePath(sandbox, pkg);
    let installPath = PackagePaths.installPath(sandbox, pkg);

    let* pkgJson =
      FetchPackage.(
        switch (fetchedKind) {
        | Linked(installPath)
        | Installed(installPath) => NpmPackageJson.ofDir(installPath)
        | Fetched(_) =>
          let* pkgJson = NpmPackageJson.ofDir(stagePath);
          let* () =
            switch (Option.bind(~f=NpmPackageJson.lifecycle, pkgJson)) {
            | Some(lifecycle) =>
              let* () = onBeforeLifecycle(stagePath);
              let* () = Lifecycle.run(pkg, stagePath, lifecycle);
              let* () =
                PackagePaths.commit(
                  ~needRewrite=true,
                  stagePath,
                  installPath,
                );
              return();
            | None =>
              let* () =
                PackagePaths.commit(
                  ~needRewrite=false,
                  stagePath,
                  installPath,
                );
              return();
            };
          return(pkgJson);
        }
      );

    RunAsync.return({pkgJson, pkg});
  };

  LwtTaskQueue.submit(queue, f);
};

let installPackages =
    (~solution, ~fetchDepsSubset, ~sandbox, ~installation, ~fetchedKindMap) => {
  let (report, finish) = Cli.createProgressReporter(~name="installing", ());
  let queue = LwtTaskQueue.create(~concurrency=40, ()); /* TODO use fetchConcurrency from cli */
  let root = Solution.root(solution);

  let tasks = Memoize.make();

  let rec visit' = (seen, pkg) => {
    let* dependencies =
      RunAsync.List.mapAndJoin(
        ~f=visit(seen),
        Solution.dependenciesBySpec(solution, fetchDepsSubset, pkg)
        |> List.filter(~f=Package.evaluateOpamPackageAvailability),
      );

    let%lwt () = report("%a", PackageId.pp, pkg.Package.id);
    let dependencies = List.filterNone(dependencies);
    install(
      ~sandbox,
      ~dependencies,
      ~solution,
      ~installation,
      ~fetchedKindMap,
      ~queue,
      pkg,
    );
  }
  and visit = (seen, pkg) => {
    let id = pkg.Package.id;
    if (!PackageId.Set.mem(id, seen)) {
      let seen = PackageId.Set.add(id, seen);
      let* {pkgJson, pkg} =
        Memoize.compute(tasks, id, () => visit'(seen, pkg));
      return(Some({pkgJson, pkg}));
    } else {
      return(None);
    };
  };

  let* rootDependencies =
    RunAsync.List.mapAndJoin(
      ~f=visit(PackageId.Set.empty),
      Solution.dependenciesBySpec(solution, fetchDepsSubset, root)
      |> List.filter(~f=Package.evaluateOpamPackageAvailability),
    );

  let* () = {
    let destBinWrapperDir /* local sandbox bin dir */ =
      SandboxSpec.binPath(sandbox.Sandbox.spec);
    let* () = Fs.createDir(destBinWrapperDir);

    let* _ = {
      let f = (seen, {pkg, pkgJson}) => {
        switch (pkgJson) {
        | Some(pkgJson) =>
          let installPath = PackagePaths.installPath(sandbox, pkg);
          let* bins =
            if (root.installConfig.pnp) {
              LinkBin.link(
                ~srcPackageDir=installPath,
                ~destBinWrapperDir,
                ~pkgJson,
              );
            } else {
              RunAsync.return([]);
            };
          let f = (seen, (name, _)) =>
            switch (StringMap.find_opt(name, seen)) {
            | None => StringMap.add(name, [pkg], seen)
            | Some(pkgs) =>
              let pkgs = [pkg, ...pkgs];
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
        | None => return(seen)
        };
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

let dumpPnp = (~solution, ~sandbox, ~installation) => {
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
};

let linkBins = (~srcPackageDir, ~destBinWrapperDir, ~pkgJson) => {
  LinkBin.link(~srcPackageDir, ~destBinWrapperDir, ~pkgJson);
};
