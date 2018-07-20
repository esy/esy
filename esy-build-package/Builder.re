module EsyBash = EsyLib.EsyBash;
module Path = EsyLib.Path;
module Option = EsyLib.Option;
module System = EsyLib.System;
open Run;

type build = {
  task: Task.t,
  sourcePath: Path.t,
  storePath: Path.t,
  installPath: Path.t,
  stagePath: Path.t,
  buildPath: Path.t,
  lockPath: Path.t,
  infoPath: Path.t,
  env: Bos.OS.Env.t,
  build: list(Bos.Cmd.t),
  install: list(Bos.Cmd.t),
};

let make = (~cfg: Config.t, task: Task.t) => {
  let%bind env = {
    let f = (k, v) =>
      fun
      | Ok(result) => {
          let%bind v = Config.renderString(~cfg, v);
          Ok(Astring.String.Map.add(k, v, result));
        }
      | error => error;
    Astring.String.Map.fold(f, task.env, Ok(Astring.String.Map.empty));
  };

  let renderCommands = (~cfg, cmds) => {
    let f = cmd => {
      let%bind cmd = Result.List.map(~f=Config.renderString(~cfg), cmd);
      return(Bos.Cmd.of_list(cmd));
    };
    Result.List.map(~f, cmds);
  };
  let%bind install = renderCommands(~cfg, task.install);
  let%bind build = renderCommands(~cfg, task.build);

  let storePath =
    switch (task.sourceType) {
    | Immutable => cfg.storePath
    | Transient => cfg.localStorePath
    };

  let%bind sourcePath = {
    let%bind sourcePath = Config.renderString(~cfg, task.sourcePath);
    return(Path.v(sourcePath));
  };
  let installPath = Path.(storePath / EsyLib.Store.installTree / task.id);
  let stagePath = Path.(storePath / EsyLib.Store.stageTree / task.id);
  let buildPath = Path.(storePath / EsyLib.Store.buildTree / task.id);
  let lockPath =
    Path.(storePath / EsyLib.Store.buildTree / task.id |> addExt(".lock"));
  let infoPath =
    Path.(storePath / EsyLib.Store.buildTree / task.id |> addExt(".info"));

  return({
    task,
    env,
    build,
    install,
    sourcePath,
    storePath,
    installPath,
    stagePath,
    buildPath,
    lockPath,
    infoPath,
  });
};

let relocateSourcePath = (config: Config.t, b: build) =>
  Run.
    /* `rsync` is one utility that DOES NOT respect Windows paths.
     *  Therefore, we need to normalize the paths to Cygwin-style (on POSIX systems, this is a no-op)
     */
    (
      {
        let%bind buildPath =
          EsyBash.normalizePathForCygwin(Bos.Cmd.p(b.buildPath));
        let%bind sourcePath =
          EsyBash.normalizePathForCygwin(Path.to_string(b.sourcePath));

        let cmd =
          Bos.Cmd.(
            empty
            % config.rsyncCmd
            % "--quiet"
            % "--archive"
            % "--exclude"
            % buildPath
            % "--exclude"
            % "node_modules"
            % "--exclude"
            % "_build"
            % "--exclude"
            % "_release"
            % "--exclude"
            % "_esybuild"
            % "--exclude"
            % "_esyinstall"
            /* The trailing "/" is important as it makes rsync to sync the contents of
             * origPath rather than the origPath itself into destPath, see "man rsync" for
             * details.
             */
            % (sourcePath ++ "/")
            % buildPath
          );

        /* `rsync` doesn't work natively on Windows, so on Windows,
         * we need to run it in the cygwin bash environment.
         */
        EsyBash.run(cmd);
      }
    );

let isRoot = (b: build) => String.equal(b.task.sourcePath, "%sandbox%");

let withLock = (lockPath: Path.t, f) => {
  let lockPath = Path.to_string(lockPath);
  let fd =
    UnixLabels.(
      openfile(
        ~mode=[O_WRONLY, O_CREAT, O_TRUNC, O_SYNC],
        ~perm=0o640,
        lockPath,
      )
    );
  let release = () => {
    UnixLabels.(lockf(fd, ~mode=F_ULOCK, ~len=0));
    Unix.close(fd);
  };
  UnixLabels.(lockf(fd, ~mode=F_TLOCK, ~len=0));
  let res =
    try (
      {
        let res = f();
        release();
        res;
      }
    ) {
    | e =>
      release();
      raise(e);
    };
  res;
};

let commitBuildToStore = (config: Config.t, b: build) => {
  open Run;
  let rewritePrefixInFile = (~origPrefix, ~destPrefix, path) => {
    let cmd =
      Bos.Cmd.(
        empty
        % config.fastreplacestringCmd
        % p(path)
        % p(origPrefix)
        % p(destPrefix)
      );
    Bos.OS.Cmd.run(cmd);
  };
  let rewriteTargetInSymlink = (~origPrefix, ~destPrefix, path) => {
    let%bind targetPath = symlink_target(path);
    switch (Path.rem_prefix(origPrefix, targetPath)) {
    | Some(basePath) =>
      let nextTargetPath = Path.append(destPrefix, basePath);
      let%bind () = rm(path);
      let%bind () = symlink(~target=nextTargetPath, path);
      ok;
    | None => ok
    };
  };
  let relocate = (path: Path.t, stats: Unix.stats) =>
    switch (stats.st_kind) {
    | Unix.S_REG =>
      rewritePrefixInFile(
        ~origPrefix=b.stagePath,
        ~destPrefix=b.installPath,
        path,
      )
    | Unix.S_LNK =>
      rewriteTargetInSymlink(
        ~origPrefix=b.stagePath,
        ~destPrefix=b.installPath,
        path,
      )
    | _ => Ok()
    };
  let%bind () =
    Bos.OS.File.write(
      Path.(b.stagePath / "_esy" / "storePrefix"),
      Path.to_string(config.storePath),
    );
  let%bind () = traverse(b.stagePath, relocate);
  let%bind () = Bos.OS.Path.move(b.stagePath, b.installPath);
  ok;
};

let relocateBuildPath = (_config: Config.t, b: build) => {
  open Run;
  let savedBuild = b.buildPath / "_build";
  let currentBuild = b.sourcePath / "_build";
  let backupBuild = b.sourcePath / "_build.prev";
  let start = (_config, _spec) => {
    let%bind () =
      if%bind (exists(currentBuild)) {
        mv(currentBuild, backupBuild);
      } else {
        ok;
      };
    let%bind () = mkdir(savedBuild);
    let%bind () = mv(savedBuild, currentBuild);
    ok;
  };
  let commit = (_config, _spec) => {
    let%bind () =
      if%bind (exists(currentBuild)) {
        mv(currentBuild, savedBuild);
      } else {
        ok;
      };
    let%bind () =
      if%bind (exists(backupBuild)) {
        mv(backupBuild, currentBuild);
      } else {
        ok;
      };
    ok;
  };
  (start, commit);
};

let findSourceModTime = (b: build) => {
  open Run;
  let visit = (path: Path.t) =>
    fun
    | Ok(maxTime) =>
      if (path == b.sourcePath) {
        Ok(maxTime);
      } else {
        let%bind {Unix.st_mtime: time, _} = Bos.OS.Path.symlink_stat(path);
        Ok(time > maxTime ? time : maxTime);
      }
    | error => error;
  let traverse =
    `Sat(
      path =>
        switch (Path.basename(path)) {
        | "node_modules" => Ok(false)
        | "_esy" => Ok(false)
        | "_release" => Ok(false)
        | "_build" => Ok(false)
        | "_install" => Ok(false)
        | base when base.[0] == '.' => Ok(false)
        | _ => Ok(true)
        },
    );
  Result.join(
    Bos.OS.Path.fold(
      ~dotfiles=true,
      ~traverse,
      visit,
      Ok(0.),
      [b.sourcePath],
    ),
  );
};

/**
 * Execute `f` within the build environment for `task`.
 */
let withBuildEnvUnlocked = (~commit=false, config: Config.t, b: build, f) => {
  open Run;

  let doNothing = (_config: Config.t, _b: build) => Run.ok;

  let (rootPath, prepareRootPath, completeRootPath) =
    switch (b.task.buildType, b.task.sourceType) {
    | (InSource, Immutable)
    | (InSource, Transient) => (b.buildPath, relocateSourcePath, doNothing)
    | (JbuilderLike, Immutable) => (
        b.buildPath,
        relocateSourcePath,
        doNothing,
      )
    | (JbuilderLike, Transient) =>
      if (isRoot(b)) {
        (b.sourcePath, doNothing, doNothing);
      } else {
        let (start, commit) = relocateBuildPath(config, b);
        (b.sourcePath, start, commit);
      }
    | (OutOfSource, Immutable)
    | (OutOfSource, Transient) => (b.sourcePath, doNothing, doNothing)
    | (Unsafe, Immutable)
    | (Unsafe, Transient) => (b.sourcePath, doNothing, doNothing)
    };
  let%bind sandboxConfig = {
    open Sandbox;
    let regex = (base, segments) => {
      let pat =
        String.concat(Path.dir_sep, [Path.to_string(base), ...segments]);
      Regex(pat);
    };
    let%bind tempPath = {
      let v = Path.v(Bos.OS.Env.opt_var("TMPDIR", ~absent="/tmp"));
      let%bind v = realpath(v);
      Ok(Path.to_string(v));
    };
    let allowWriteToSourcePath =
      switch (b.task.buildType) {
      | Unsafe => [Subpath(Path.to_string(b.sourcePath))]
      | JbuilderLike => [
          Subpath(Path.to_string(b.sourcePath / "_build")),
          regex(b.sourcePath, [".*", "[^/]*\\.install"]),
          regex(b.sourcePath, ["[^/]*\\.install"]),
          regex(b.sourcePath, [".*", "[^/]*\\.opam"]),
          regex(b.sourcePath, ["[^/]*\\.opam"]),
          regex(b.sourcePath, [".*", "jbuild-ignore"]),
        ]
      | _ => []
      };
    Ok(
      allowWriteToSourcePath
      @ [
        regex(b.sourcePath, [".*", "\\.merlin"]),
        regex(b.sourcePath, ["\\.merlin"]),
        Subpath(Path.to_string(b.buildPath)),
        Subpath(Path.to_string(b.stagePath)),
        Subpath("/private/tmp"),
        Subpath("/tmp"),
        Subpath(tempPath),
      ],
    );
  };
  let env =
    switch (Bos.OS.Env.var("TERM")) {
    | Some(term) => Astring.String.Map.add("TERM", term, b.env)
    | None => b.env
    };
  let%bind prepare = Sandbox.sandboxExec({allowWrite: sandboxConfig});
  let path =
    switch (Astring.String.Map.find("PATH", env)) {
    | Some(path) => String.split_on_char(System.envSep.[0], path)
    | None => []
    };
  let run = cmd => {
    let%bind ((), (_runInfo, runStatus)) = {
      let%bind cmd = EsyLib.Cmd.ofBosCmd(cmd);
      let%bind cmd = EsyLib.Cmd.resolveInvocation(path, cmd);
      let cmd = EsyLib.Cmd.toBosCmd(cmd);
      let%bind exec = prepare(~env, cmd);
      Bos.OS.Cmd.(in_null |> exec(~err=Bos.OS.Cmd.err_run_out) |> out_stdout);
    };
    switch (runStatus) {
    | `Exited(0) => Ok()
    | status => Error(`CommandError((cmd, status)))
    };
  };
  let runInteractive = cmd => {
    let%bind ((), (_runInfo, runStatus)) = {
      let%bind cmd = EsyLib.Cmd.ofBosCmd(cmd);
      let%bind cmd = EsyLib.Cmd.resolveInvocation(path, cmd);
      let cmd = EsyLib.Cmd.toBosCmd(cmd);
      let%bind exec = prepare(~env, cmd);
      Bos.OS.Cmd.(in_stdin |> exec(~err=Bos.OS.Cmd.err_stderr) |> out_stdout);
    };
    switch (runStatus) {
    | `Exited(0) => Ok()
    | status => Error(`CommandError((cmd, status)))
    };
  };
  /*
   * Prepare build/install.
   */
  let prepare = () => {
    let%bind () = rmdir(b.installPath);
    let%bind () = rmdir(b.stagePath);
    let%bind () = mkdir(b.stagePath);
    let%bind () = mkdir(b.stagePath / "bin");
    let%bind () = mkdir(b.stagePath / "lib");
    let%bind () = mkdir(b.stagePath / "etc");
    let%bind () = mkdir(b.stagePath / "sbin");
    let%bind () = mkdir(b.stagePath / "man");
    let%bind () = mkdir(b.stagePath / "share");
    let%bind () = mkdir(b.stagePath / "doc");
    let%bind () = mkdir(b.stagePath / "_esy");
    let%bind () =
      switch (b.task.sourceType, b.task.buildType) {
      | (Immutable, _)
      | (_, InSource) =>
        let%bind () = rmdir(b.buildPath);
        let%bind () = mkdir(b.buildPath);
        ok;
      | _ =>
        let%bind () = mkdir(b.buildPath);
        ok;
      };
    let%bind () = prepareRootPath(config, b);
    let%bind () = mkdir(b.buildPath / "_esy");
    ok;
  };
  /*
   * Finalize build/install.
   */
  let finalize = result =>
    switch (result) {
    | Ok () =>
      let%bind () =
        if (commit) {
          commitBuildToStore(config, b);
        } else {
          ok;
        };
      let%bind () = completeRootPath(config, b);
      ok;
    | error =>
      let%bind () = completeRootPath(config, b);
      error;
    };
  let%bind () = prepare();
  let result = withCwd(rootPath, ~f=f(run, runInteractive));
  let%bind () = finalize(result);
  result;
};

let withBuildEnv = (~commit=false, ~cfg: Config.t, task: Task.t, f) => {
  let%bind b = make(~cfg, task);
  let%bind () = Store.init(cfg.storePath);
  let%bind () = Store.init(cfg.localStorePath);
  let perform = () => withBuildEnvUnlocked(~commit, cfg, b, f);
  switch (b.task.sourceType) {
  | SourceType.Transient => withLock(b.lockPath, perform)
  | SourceType.Immutable => perform()
  };
};

let build = (~buildOnly=true, ~force=false, ~cfg: Config.t, task: Task.t) => {
  let%bind b = make(~cfg, task);
  Logs.debug(m => m("start %s", b.task.id));
  let performBuild = sourceModTime => {
    Logs.debug(m => m("building"));
    Logs.app(m =>
      m("# esy-build-package: building: %s@%s", b.task.name, b.task.version)
    );
    let runBuildAndInstall = (run, _runInteractive, ()) => {
      let runList = cmds => {
        let rec aux = cmds =>
          switch (cmds) {
          | [] => Ok()
          | [cmd, ...cmds] =>
            Logs.app(m =>
              m("# esy-build-package: running: %s", Bos.Cmd.to_string(cmd))
            );
            switch (run(cmd)) {
            | Ok(_) => aux(cmds)
            | Error(err) => Error(err)
            };
          };
        aux(cmds);
      };
      let%bind () = runList(b.build);
      let%bind () =
        if (! buildOnly) {
          runList(b.install);
        } else {
          ok;
        };
      ok;
    };
    let startTime = Unix.gettimeofday();
    let%bind () =
      withBuildEnv(~commit=! buildOnly, ~cfg, task, runBuildAndInstall);
    let%bind info = {
      let%bind sourceModTime =
        switch (sourceModTime, b.task.sourceType) {
        | (None, SourceType.Transient) =>
          if (isRoot(b)) {
            Ok(None);
          } else {
            Logs.debug(m => m("computing build mtime"));
            let%bind v = findSourceModTime(b);
            Ok(Some(v));
          }
        | (v, _) => Ok(v)
        };
      Ok(
        BuildInfo.{
          sourceModTime,
          timeSpent: Unix.gettimeofday() -. startTime,
        },
      );
    };
    BuildInfo.toFile(b.infoPath, info);
  };
  switch (force, b.task.sourceType) {
  | (true, _) =>
    Logs.debug(m => m("forcing build"));
    performBuild(None);
  | (false, SourceType.Transient) =>
    if (isRoot(b)) {
      performBuild(None);
    } else {
      Logs.debug(m => m("checking for staleness"));
      let%bind info = BuildInfo.ofFile(b.infoPath);
      let prevSourceModTime =
        Option.bind(~f=v => v.BuildInfo.sourceModTime, info);
      let%bind sourceModTime = findSourceModTime(b);
      switch (prevSourceModTime) {
      | Some(prevSourceModTime) when sourceModTime > prevSourceModTime =>
        performBuild(Some(sourceModTime))
      | None => performBuild(Some(sourceModTime))
      | Some(_) =>
        Logs.debug(m => m("source code is not modified, skipping"));
        ok;
      };
    }
  | (false, SourceType.Immutable) =>
    let%bind installPathExists = exists(b.installPath);
    if (installPathExists) {
      Logs.debug(m => m("build exists in store, skipping"));
      ok;
    } else {
      performBuild(None);
    };
  };
};
