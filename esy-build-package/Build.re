module EsyBash = EsyLib.EsyBash;
module Path = EsyLib.Path;
module Option = EsyLib.Option;
module System = EsyLib.System;
open Run;

type t = {
  task: Task.t,
  sourcePath: Path.t,
  storePath: Path.t,
  installPath: Path.t,
  stagePath: Path.t,
  buildPath: Path.t,
  lockPath: Path.t,
  infoPath: Path.t,
  env: Bos.OS.Env.t,
  build: list(Cmd.t),
  install: list(Cmd.t),
  sandbox: Sandbox.sandbox,
};

type build = t;

let make = (~cfg: Config.t, task: Task.t) => {
  let%bind env = {
    let f = (k, v) =>
      fun
      | Ok(result) => {
          let%bind v = Config.Value.toString(~cfg, v);
          Ok(Astring.String.Map.add(k, v, result));
        }
      | error => error;
    Astring.String.Map.fold(f, task.env, Ok(Astring.String.Map.empty));
  };

  let renderCommands = (~cfg, cmds) => {
    let f = cmd => {
      let%bind cmd =
        EsyLib.Result.List.map(~f=Config.Value.toString(~cfg), cmd);
      return(Cmd.of_list(cmd));
    };
    EsyLib.Result.List.map(~f, cmds);
  };
  let%bind install = renderCommands(~cfg, task.install);
  let%bind build = renderCommands(~cfg, task.build);

  let storePath =
    switch (task.sourceType) {
    | Immutable => cfg.storePath
    | Transient => cfg.localStorePath
    };

  let%bind sourcePath = {
    let%bind sourcePath = Config.Value.toString(~cfg, task.sourcePath);
    return(Path.v(sourcePath));
  };
  let installPath = Path.(storePath / EsyLib.Store.installTree / task.id);
  let stagePath = Path.(storePath / EsyLib.Store.stageTree / task.id);
  let buildPath = Path.(storePath / EsyLib.Store.buildTree / task.id);
  let lockPath =
    Path.(storePath / EsyLib.Store.buildTree / task.id |> addExt(".lock"));
  let infoPath =
    Path.(storePath / EsyLib.Store.buildTree / task.id |> addExt(".info"));

  let%bind sandbox = {
    let%bind config = {
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
        | Unsafe => [Subpath(Path.to_string(sourcePath))]
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
      Ok({
        allowWrite:
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
      });
    };
    Sandbox.init(config);
  };

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
    sandbox,
  });
};

let relocateSourcePath = (b: build) : Run.t(unit, _) => {
  let excludePaths =
    List.fold_left(
      (set, p) => Path.Set.add(Path.(b.sourcePath / p), set),
      Path.Set.empty,
      [
        "node_modules",
        "_build",
        "_install",
        "_release",
        "_esybuild",
        "_esyinstall",
      ],
    );

  let traverse = `Sat(p => Ok(! Path.Set.mem(p, excludePaths)));

  let rebasePath = (prevRoot, nextRoot, path) =>
    switch (Fpath.relativize(~root=prevRoot, path)) {
    | Some(p) => Path.(nextRoot /\/ p)
    | None => path
    };

  let f = (path, acc) =>
    switch (acc) {
    | Ok () =>
      if (Path.equal(path, b.sourcePath)) {
        Ok();
      } else {
        let%bind stats = Bos.OS.Path.symlink_stat(path);
        let nextPath = rebasePath(b.sourcePath, b.buildPath, path);
        switch (stats.Unix.st_kind) {
        | Unix.S_DIR =>
          let _ = Bos.OS.Dir.create(nextPath);
          Ok();
        | Unix.S_REG =>
          let%bind data = Bos.OS.File.read(path);
          let%bind () = Bos.OS.File.write(nextPath, data);
          Bos.OS.Path.Mode.set(nextPath, stats.Unix.st_perm);
        | Unix.S_LNK =>
          let%bind targetPath = Bos.OS.Path.symlink_target(path);
          let nextTargetPath =
            rebasePath(b.sourcePath, b.buildPath, targetPath);
          Bos.OS.Path.symlink(~target=nextTargetPath, nextPath);
        | _ => /* ignore everything else */ Ok()
        };
      }
    | Error(err) => Error(err)
    };

  EsyLib.Result.join(
    Bos.OS.Path.fold(~dotfiles=true, ~traverse, f, Ok(), [b.sourcePath]),
  );
};

let isRoot = (b: t) =>
  Config.Value.equal(b.task.sourcePath, Config.Value.sandbox);

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

let commitBuildToStore = (config: Config.t, b: t) => {
  let rewritePrefixInFile = (~origPrefix, ~destPrefix, path) => {
    let cmd =
      Cmd.(
        empty
        % config.fastreplacestringCmd
        % p(path)
        % p(origPrefix)
        % p(destPrefix)
      );
    Bos.OS.Cmd.run(cmd);
  };
  let rewriteTargetInSymlink = (~origPrefix, ~destPrefix, path) => {
    let%bind targetPath = symlinkTarget(path);
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

let relocateBuildPath = (_config: Config.t, b: t) => {
  let savedBuild = b.buildPath / "_build";
  let currentBuild = b.sourcePath / "_build";
  let backupBuild = b.sourcePath / "_build.prev";
  let start = _build => {
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
  let commit = _build => {
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

let findSourceModTime = (b: t) => {
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
  EsyLib.Result.join(
    Bos.OS.Path.fold(
      ~dotfiles=true,
      ~traverse,
      visit,
      Ok(0.),
      [b.sourcePath],
    ),
  );
};

let withBuild = (~commit=false, ~cfg: Config.t, task: Task.t, f) => {
  let%bind b = make(~cfg, task);

  let initStoreAt = (path: Path.t) => {
    let%bind () = mkdir(Path.(path / "i"));
    let%bind () = mkdir(Path.(path / "b"));
    let%bind () = mkdir(Path.(path / "s"));
    Ok();
  };

  let%bind () = initStoreAt(cfg.storePath);
  let%bind () = initStoreAt(cfg.localStorePath);

  let perform = () => {
    let doNothing = (_b: t) : Run.t(unit, _) => Run.ok;

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
          let (start, commit) = relocateBuildPath(cfg, b);
          (b.sourcePath, start, commit);
        }
      | (OutOfSource, Immutable)
      | (OutOfSource, Transient) => (b.sourcePath, doNothing, doNothing)
      | (Unsafe, Immutable)
      | (Unsafe, Transient) => (b.sourcePath, doNothing, doNothing)
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
      let%bind () = prepareRootPath(b);
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
            commitBuildToStore(cfg, b);
          } else {
            ok;
          };
        let%bind () = completeRootPath(b);
        ok;
      | error =>
        let%bind () = completeRootPath(b);
        error;
      };
    let%bind () = prepare();
    let result = withCwd(rootPath, ~f=() => f(b));
    let%bind () = finalize(result);
    result;
  };

  switch (b.task.sourceType) {
  | SourceType.Transient => withLock(b.lockPath, perform)
  | SourceType.Immutable => perform()
  };
};

let runCommand = (b, cmd) => {
  let env =
    switch (Bos.OS.Env.var("TERM")) {
    | Some(term) => Astring.String.Map.add("TERM", term, b.env)
    | None => b.env
    };
  let path =
    switch (Astring.String.Map.find("PATH", env)) {
    | Some(path) => String.split_on_char(System.Environment.sep.[0], path)
    | None => []
    };

  let%bind ((), (_runInfo, runStatus)) = {
    let%bind cmd = EsyLib.Cmd.ofBosCmd(cmd);
    let%bind cmd = EsyLib.Cmd.resolveInvocation(path, cmd);
    let cmd = EsyLib.Cmd.toBosCmd(cmd);
    let%bind exec = Sandbox.exec(~env, b.sandbox, cmd);
    Bos.OS.Cmd.(in_null |> exec(~err=Bos.OS.Cmd.err_run_out) |> out_stdout);
  };
  switch (runStatus) {
  | `Exited(0) => Ok()
  | status => Error(`CommandError((cmd, status)))
  };
};

let runCommandInteractive = (b, cmd) => {
  let env =
    switch (Bos.OS.Env.var("TERM")) {
    | Some(term) => Astring.String.Map.add("TERM", term, b.env)
    | None => b.env
    };
  let path =
    switch (Astring.String.Map.find("PATH", env)) {
    | Some(path) => String.split_on_char(System.Environment.sep.[0], path)
    | None => []
    };
  let%bind ((), (_runInfo, runStatus)) = {
    let%bind cmd = EsyLib.Cmd.ofBosCmd(cmd);
    let%bind cmd = EsyLib.Cmd.resolveInvocation(path, cmd);
    let cmd = EsyLib.Cmd.toBosCmd(cmd);
    let%bind exec = Sandbox.exec(~env, b.sandbox, cmd);
    Bos.OS.Cmd.(in_stdin |> exec(~err=Bos.OS.Cmd.err_stderr) |> out_stdout);
  };
  switch (runStatus) {
  | `Exited(0) => Ok()
  | status => Error(`CommandError((cmd, status)))
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
    let runBuildAndInstall = b => {
      let runList = cmds => {
        let rec aux = cmds =>
          switch (cmds) {
          | [] => Ok()
          | [cmd, ...cmds] =>
            Logs.app(m =>
              m("# esy-build-package: running: %s", Cmd.to_string(cmd))
            );
            switch (runCommand(b, cmd)) {
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
      withBuild(~commit=! buildOnly, ~cfg, task, runBuildAndInstall);
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
