module Path = EsyLib.Path;
module Option = EsyLib.Option;

let relocateSourcePath = (config: Config.t, task: BuildTask.t) => {
  open Run;

  /* `rsync` is one utility that DOES NOT respect Windows paths.
   *  Therefore, we need to normalize the paths to Cygwin-style (on POSIX systems, this is a no-op)
   */
  let%bind buildPath = EsyBash.normalizePathForCygwin(Bos.Cmd.p(task.buildPath));
  let%bind sourcePath = EsyBash.normalizePathForCygwin(Path.to_string(task.sourcePath));

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
};

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

let commitBuildToStore = (config: Config.t, task: BuildTask.t) => {
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
        ~origPrefix=task.stagePath,
        ~destPrefix=task.installPath,
        path,
      )
    | Unix.S_LNK =>
      rewriteTargetInSymlink(
        ~origPrefix=task.stagePath,
        ~destPrefix=task.installPath,
        path,
      )
    | _ => Ok()
    };
  let%bind () =
    Bos.OS.File.write(
      Path.(task.stagePath / "_esy" / "storePrefix"),
      Path.to_string(config.storePath),
    );
  let%bind () = traverse(task.stagePath, relocate);
  let%bind () = Bos.OS.Path.move(task.stagePath, task.installPath);
  ok;
};

let relocateBuildPath = (_config: Config.t, task: BuildTask.t) => {
  open Run;
  let savedBuild = task.buildPath / "_build";
  let currentBuild = task.sourcePath / "_build";
  let backupBuild = task.sourcePath / "_build.prev";
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

let findSourceModTime = (task: BuildTask.t) => {
  open Run;
  let visit = (path: Path.t) =>
    fun
    | Ok(maxTime) =>
      if (path == task.sourcePath) {
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
      [task.sourcePath],
    ),
  );
};

let doNothing = (_config: Config.t, _spec: BuildTask.t) => Run.ok;

/**
 * Execute `f` within the build environment for `task`.
 */
let withBuildEnvUnlocked =
    (~commit=false, config: Config.t, task: BuildTask.t, f) => {
  open Run;
  let {BuildTask.sourcePath, installPath, buildPath, stagePath, _} = task;
  let (rootPath, prepareRootPath, completeRootPath) =
    switch (task.buildType, task.sourceType) {
    | (InSource, _) => (buildPath, relocateSourcePath, doNothing)
    | (JbuilderLike, Immutable) => (buildPath, relocateSourcePath, doNothing)
    | (JbuilderLike, Transient) =>
      if (BuildTask.isRoot(~config, task)) {
        (sourcePath, doNothing, doNothing);
      } else {
        let (start, commit) = relocateBuildPath(config, task);
        (sourcePath, start, commit);
      }
    | (OutOfSource, _) => (sourcePath, doNothing, doNothing)
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
      switch (task.buildType) {
      | JbuilderLike => [
          Subpath(Path.to_string(sourcePath / "_build")),
          regex(sourcePath, [".*", "[^/]*\\.install"]),
          regex(sourcePath, ["[^/]*\\.install"]),
          regex(sourcePath, [".*", "[^/]*\\.opam"]),
          regex(sourcePath, ["[^/]*\\.opam"]),
          regex(sourcePath, [".*", "jbuild-ignore"]),
        ]
      | _ => []
      };
    Ok(
      allowWriteToSourcePath
      @ [
        regex(sourcePath, [".*", "\\.merlin"]),
        regex(sourcePath, ["\\.merlin"]),
        Subpath(Path.to_string(buildPath)),
        Subpath(Path.to_string(stagePath)),
        Subpath("/private/tmp"),
        Subpath("/tmp"),
        Subpath(tempPath),
      ],
    );
  };
  let env =
    switch (Bos.OS.Env.var("TERM")) {
    | Some(term) => Astring.String.Map.add("TERM", term, task.env)
    | None => task.env
    };
  let%bind exec = Sandbox.sandboxExec({allowWrite: sandboxConfig});
  let path =
    switch (Astring.String.Map.find("PATH", env)) {
    | Some(path) => String.split_on_char(':', path)
    | None => []
    };
  let run = cmd => {
    let%bind cmd = EsyLib.Cmd.ofBosCmd(cmd);
    let%bind cmd = EsyLib.Cmd.resolveInvocation(path, cmd);
    let cmd = EsyLib.Cmd.toBosCmd(cmd);
    let%bind ((), (_runInfo, runStatus)) =
      Bos.OS.Cmd.(
        in_null |> exec(~err=Bos.OS.Cmd.err_run_out, ~env, cmd) |> out_stdout
      );
    switch (runStatus) {
    | `Exited(0) => Ok()
    | status => Error(`CommandError((cmd, status)))
    };
  };
  let runInteractive = cmd => {
    let%bind cmd = EsyLib.Cmd.ofBosCmd(cmd);
    let%bind cmd = EsyLib.Cmd.resolveInvocation(path, cmd);
    let cmd = EsyLib.Cmd.toBosCmd(cmd);
    let%bind ((), (_runInfo, runStatus)) =
      Bos.OS.Cmd.(
        in_stdin |> exec(~err=Bos.OS.Cmd.err_stderr, ~env, cmd) |> out_stdout
      );
    switch (runStatus) {
    | `Exited(0) => Ok()
    | status => Error(`CommandError((cmd, status)))
    };
  };
  /*
   * Prepare build/install.
   */
  let prepare = () => {
    let%bind () = rmdir(installPath);
    let%bind () = rmdir(stagePath);
    let%bind () = mkdir(stagePath);
    let%bind () = mkdir(stagePath / "bin");
    let%bind () = mkdir(stagePath / "lib");
    let%bind () = mkdir(stagePath / "etc");
    let%bind () = mkdir(stagePath / "sbin");
    let%bind () = mkdir(stagePath / "man");
    let%bind () = mkdir(stagePath / "share");
    let%bind () = mkdir(stagePath / "doc");
    let%bind () = mkdir(stagePath / "_esy");
    let%bind () =
      switch (task.sourceType, task.buildType) {
      | (Immutable, _)
      | (_, InSource) =>
        let%bind () = rmdir(buildPath);
        let%bind () = mkdir(buildPath);
        ok;
      | _ =>
        let%bind () = mkdir(buildPath);
        ok;
      };
    let%bind () = prepareRootPath(config, task);
    let%bind () = mkdir(buildPath / "_esy");
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
          commitBuildToStore(config, task);
        } else {
          ok;
        };
      let%bind () = completeRootPath(config, task);
      ok;
    | error =>
      let%bind () = completeRootPath(config, task);
      error;
    };
  let%bind () = prepare();
  let result = withCwd(rootPath, ~f=f(run, runInteractive));
  let%bind () = finalize(result);
  result;
};

let withBuildEnv = (~commit=false, config: Config.t, task: BuildTask.t, f) =>
  Run.(
    {
      let%bind () = Store.init(config.storePath);
      let%bind () = Store.init(config.localStorePath);
      let perform = () => withBuildEnvUnlocked(~commit, config, task, f);
      switch (task.sourceType) {
      | BuildTask.SourceType.Transient => withLock(task.lockPath, perform)
      | BuildTask.SourceType.Immutable => perform()
      };
    }
  );

let build =
    (~buildOnly=true, ~force=false, config: Config.t, task: BuildTask.t) => {
  open Run;
  Logs.debug(m => m("start %s", task.id));
  let performBuild = sourceModTime => {
    Logs.debug(m => m("building"));
    Logs.app(m =>
      m("# esy-build-package: building: %s@%s", task.name, task.version)
    );
    let runBuildAndInstall = (run, _runInteractive, ()) => {
      let runList = cmds => {
        let rec _runList = cmds =>
          switch (cmds) {
          | [] => Ok()
          | [cmd, ...cmds] =>
            Logs.app(m =>
              m("# esy-build-package: running: %s", Bos.Cmd.to_string(cmd))
            );
            switch (run(cmd)) {
            | Ok(_) => _runList(cmds)
            | Error(err) => Error(err)
            };
          };
        _runList(cmds);
      };
      let {BuildTask.build, install, _} = task;
      let%bind () = runList(build);
      let%bind () =
        if (! buildOnly) {
          runList(install);
        } else {
          ok;
        };
      ok;
    };
    let startTime = Unix.gettimeofday();
    let%bind () =
      withBuildEnv(~commit=! buildOnly, config, task, runBuildAndInstall);
    let%bind info = {
      let%bind sourceModTime =
        switch (sourceModTime, task.sourceType) {
        | (None, BuildTask.SourceType.Transient) =>
          if (BuildTask.isRoot(~config, task)) {
            Ok(None);
          } else {
            Logs.debug(m => m("computing build mtime"));
            let%bind v = findSourceModTime(task);
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
    BuildInfo.write(task, info);
  };
  switch (force, task.sourceType) {
  | (true, _) =>
    Logs.debug(m => m("forcing build"));
    performBuild(None);
  | (false, BuildTask.SourceType.Transient) =>
    if (BuildTask.isRoot(~config, task)) {
      performBuild(None);
    } else {
      Logs.debug(m => m("checking for staleness"));
      let info = BuildInfo.read(task);
      let prevSourceModTime =
        Option.bind(~f=v => v.BuildInfo.sourceModTime, info);
      let%bind sourceModTime = findSourceModTime(task);
      switch (prevSourceModTime) {
      | Some(prevSourceModTime) when sourceModTime > prevSourceModTime =>
        performBuild(Some(sourceModTime))
      | None => performBuild(Some(sourceModTime))
      | Some(_) =>
        Logs.debug(m => m("source code is not modified, skipping"));
        ok;
      };
    }
  | (false, BuildTask.SourceType.Immutable) =>
    let%bind installPathExists = exists(task.installPath);
    if (installPathExists) {
      Logs.debug(m => m("build exists in store, skipping"));
      ok;
    } else {
      performBuild(None);
    };
  };
};
