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

let isRoot = (build: t) =>
  Config.Value.equal(build.task.sourcePath, Config.Value.sandbox);

let regex = (base, segments) => {
  let pat =
    String.concat(Path.dir_sep, [Path.to_string(base), ...segments]);
  Sandbox.Regex(pat);
};

module type LIFECYCLE = {
  let getRootPath: build => Path.t;
  let getAllowedToWritePaths: (Task.t, Path.t) => list(Sandbox.pattern);
  let prepare: build => Run.t(unit, _);
  let finalize: build => Run.t(unit, _);
};

/*

   A lifecycle of a build which is performed in its original source tree and
   adheres to all esy convention (most importantly uses $cur__target_dir for its
   build dir).

 */
module OutOfSourceLifecycle: LIFECYCLE = {
  let getRootPath = build => build.sourcePath;
  let getAllowedToWritePaths = (_task, _sourcePath) => [];
  let prepare = _build => Ok();
  let finalize = (build: build) =>
    if (isRoot(build)) {
      symlink(
        ~force=true,
        ~target=build.buildPath,
        Path.(build.sourcePath / "_build"),
      );
    } else {
      ok;
    };
};

/*

   A lifecycle which defensively copies all project source tree into build dir
   before running a build.

   This is designed so that projects which don't implement out of source builds
   still can be used safely with multiple sandboxes.

   Also we use this lifecycle when building into global store as we want as much
   safety as possible.

 */
module RelocateSourceLifecycle: LIFECYCLE = {
  let getRootPath = build => build.buildPath;
  let getAllowedToWritePaths = (_task, _sourcePath) => [];

  let prepare = (build: build) => {
    let%bind () = rm(build.buildPath);
    let%bind () = mkdir(build.buildPath);
    let%bind () = {
      let ignore = [
        "node_modules",
        "_build",
        "_install",
        "_release",
        "_esybuild",
        "_esyinstall",
      ];
      copyContents(~from=build.sourcePath, ~ignore, build.buildPath);
    };
    ok;
  };

  let finalize = _build => Ok();
};

/*

  A special lifecycle designed to be compatible with jbuilder's use of _build
  subdirectory as a build dir.

 */
module JBuilderLifecycle: LIFECYCLE = {
  let getRootPath = (build: build) => build.sourcePath;
  let getAllowedToWritePaths = (_task, sourcePath) =>
    Sandbox.[
      Subpath(Path.to_string(sourcePath / "_build")),
      regex(sourcePath, [".*", "[^/]*\\.install"]),
      regex(sourcePath, ["[^/]*\\.install"]),
      regex(sourcePath, [".*", "[^/]*\\.opam"]),
      regex(sourcePath, ["[^/]*\\.opam"]),
      regex(sourcePath, [".*", "jbuild-ignore"]),
    ];

  let prepareImpl = (build: build) => {
    let savedBuild = build.buildPath / "_build";
    let currentBuild = build.sourcePath / "_build";
    let backupBuild = build.sourcePath / "_build.prev";

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

  let commitImpl = (build: build) => {
    let savedBuild = build.buildPath / "_build";
    let currentBuild = build.sourcePath / "_build";
    let backupBuild = build.sourcePath / "_build.prev";

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

  let prepare = (build: build) =>
    if (isRoot(build)) {
      ok;
    } else {
      prepareImpl(build);
    };

  let finalize = (build: build) =>
    if (isRoot(build)) {
      ok;
    } else {
      commitImpl(build);
    };
};

/*

   Same as OutOfSourceLifecycle but allows to write into project's root
   directory.

   This makes it unsafe by definiton. Projects which use such lifecycle for its
   builds can't be linked to other sandboxes as they pollute their own source
   tree.

   Currently only opam packages use this strategy.

 */
module UnsafeLifecycle: LIFECYCLE = {
  let getRootPath = (build: build) => build.sourcePath;

  let getAllowedToWritePaths = (_task, sourcePath) =>
    Sandbox.[Subpath(Path.to_string(sourcePath))];

  let prepare = _build => Ok();
  let finalize = _build => Ok();
};

let configureBuild = (~cfg: Config.t, task: Task.t) => {
  let (module Lifecycle): (module LIFECYCLE) =
    switch (task.buildType, task.sourceType) {
    | (InSource, Immutable) => (module RelocateSourceLifecycle)
    | (InSource, Transient) => (module RelocateSourceLifecycle)
    | (JbuilderLike, Immutable) => (module RelocateSourceLifecycle)
    | (JbuilderLike, Transient) => (module JBuilderLifecycle)
    | (OutOfSource, Immutable) => (module OutOfSourceLifecycle)
    | (OutOfSource, Transient) => (module OutOfSourceLifecycle)
    | (Unsafe, Immutable) => (module RelocateSourceLifecycle)
    | (Unsafe, Transient) => (module UnsafeLifecycle)
    };

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
      let%bind tempPath = {
        let v = Path.v(Bos.OS.Env.opt_var("TMPDIR", ~absent="/tmp"));
        let%bind v = realpath(v);
        Ok(Path.to_string(v));
      };
      Ok({
        Sandbox.allowWrite: [
          regex(sourcePath, [".*", "\\.merlin"]),
          regex(sourcePath, ["\\.merlin"]),
          regex(sourcePath, [".*\\.install"]),
          Subpath(Path.to_string(buildPath)),
          Subpath(Path.to_string(stagePath)),
          Subpath("/private/tmp"),
          Subpath("/tmp"),
          Subpath(tempPath),
          ...Lifecycle.getAllowedToWritePaths(task, sourcePath),
        ],
      });
    };
    Sandbox.init(config);
  };

  return((
    {
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
    },
    (module Lifecycle): (module LIFECYCLE),
  ));
};

module Installer =
  EsyInstaller.Installer.Make({
    type computation('v) =
      Run.t(
        'v,
        [ | `Msg(string) | `CommandError(Cmd.t, Bos.OS.Cmd.status)],
      );

    let return = Run.return;
    let error = Run.error;
    let handle = v =>
      switch (v) {
      | Ok(v) => return(Ok(v))
      | Error(`Msg(err)) => return(Error(err))
      | Error(`CommandError(cmd, _)) =>
        let msg = "Error running command: " ++ Bos.Cmd.to_string(cmd);
        return(Error(msg));
      };
    let bind = Run.bind;

    module Fs = {
      let read = Run.read;
      let write = Run.write;
      let stat = Run.lstat;
      let readdir = Run.ls;
      let mkdir = Run.mkdir;
    };
  });

let install = (~prefixPath, ~rootPath, ~installFilename=?, ()) => {
  Logs.app(m =>
    m("# esy-build-package: installing using built-in installer")
  );
  let res = Installer.run(~prefixPath, ~rootPath, installFilename);
  Run.coerceFromClosed(res);
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

let commitBuildToStore = (config: Config.t, build: build) => {
  let rewritePrefixInFile = (~origPrefix, ~destPrefix, path) => {
    let cmd =
      Cmd.(
        empty
        % config.fastreplacestringCmd
        % p(path)
        % origPrefix
        % destPrefix
      );
    Bos.OS.Cmd.run(cmd);
  };
  let rewritePrefixesInFile = (~origPrefix, ~destPrefix, path) => {
    let origPrefixString = Path.to_string(origPrefix);
    let destPrefixString = Path.to_string(destPrefix);
    switch (System.Platform.host) {
    | Windows =>
        /* On Windows, the slashes could be either `/` or windows-style `\` */
        /* We'll replace both styles */
        let%bind () = rewritePrefixInFile(~origPrefix=origPrefixString, ~destPrefix=destPrefixString, path);
        let normalizedOrigPrefix = Path.normalizePathSlashes(origPrefixString);
        let normalizedDestPrefix = Path.normalizePathSlashes(destPrefixString);
        let%bind () = rewritePrefixInFile(~origPrefix=normalizedOrigPrefix, ~destPrefix=normalizedDestPrefix, path);
        ok;
    | _ =>
        rewritePrefixInFile(~origPrefix=origPrefixString, ~destPrefix=destPrefixString, path);
    }
  };
  let rewriteTargetInSymlink = (~origPrefix, ~destPrefix, path) => {
    let%bind targetPath = readlink(path);
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
      rewritePrefixesInFile(
        ~origPrefix=build.stagePath,
        ~destPrefix=build.installPath,
        path,
      )
    | Unix.S_LNK =>
      rewriteTargetInSymlink(
        ~origPrefix=build.stagePath,
        ~destPrefix=build.installPath,
        path,
      )
    | _ => Ok()
    };
  let%bind () =
    write(
      ~data=Path.to_string(config.storePath),
      Path.(build.stagePath / "_esy" / "storePrefix"),
    );
  let%bind () = traverse(build.stagePath, relocate);
  let%bind () = mv(build.stagePath, build.installPath);
  ok;
};

let findSourceModTime = (build: build) => {
  let visit = (path: Path.t) =>
    fun
    | Ok(maxTime) =>
      if (path == build.sourcePath) {
        Ok(maxTime);
      } else {
        let%bind {Unix.st_mtime: time, _} = lstat(path);
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
      [build.sourcePath],
    ),
  );
};

let withBuild = (~commit=false, ~cfg: Config.t, task: Task.t, f) => {
  let%bind (build, lifecycle) = configureBuild(~cfg, task);

  let (module Lifecycle): (module LIFECYCLE) = lifecycle;

  let initStoreAt = (path: Path.t) => {
    let%bind () = mkdir(Path.(path / "i"));
    let%bind () = mkdir(Path.(path / "b"));
    let%bind () = mkdir(Path.(path / "s"));
    Ok();
  };

  let%bind () = initStoreAt(cfg.storePath);
  let%bind () = initStoreAt(cfg.localStorePath);

  let perform = () => {
    let%bind () = rm(build.installPath);
    let%bind () = rm(build.stagePath);
    let%bind () = mkdir(build.stagePath);
    let%bind () = mkdir(build.stagePath / "bin");
    let%bind () = mkdir(build.stagePath / "lib");
    let%bind () = mkdir(build.stagePath / "etc");
    let%bind () = mkdir(build.stagePath / "sbin");
    let%bind () = mkdir(build.stagePath / "man");
    let%bind () = mkdir(build.stagePath / "share");
    let%bind () = mkdir(build.stagePath / "doc");
    let%bind () = mkdir(build.stagePath / "_esy");
    let%bind () = Lifecycle.prepare(build);
    let%bind () = mkdir(build.buildPath);
    let%bind () = mkdir(build.buildPath / "_esy");

    let rootPath = Lifecycle.getRootPath(build);

    /*
       Detect if there's dune-project which means this is a dune based sandbox,
       we need to make dune ignore node_modules as it might recurse into it and
       error.
     */
    let%bind () = {
      let%bind hasDune = exists(rootPath / "dune-project");
      let%bind hasNodeModules = exists(rootPath / "node_modules");
      if (hasDune && hasNodeModules) {
        let%bind items = ls(rootPath / "node_modules");
        let items = items |> List.map(Path.toString) |> String.concat(" ");
        let data = "(ignored_subdirs (" ++ items ++ "))\n";
        let%bind () = write(~data, rootPath / "node_modules" / "dune");
        ok;
      } else {
        ok;
      };
    };

    let%bind () =
      switch (withCwd(rootPath, ~f=() => f(build))) {
      | Ok () =>
        let%bind () =
          if (commit) {
            commitBuildToStore(cfg, build);
          } else {
            ok;
          };
        let%bind () = Lifecycle.finalize(build);
        ok;
      | error =>
        let%bind () = Lifecycle.finalize(build);
        error;
      };

    ok;
  };

  switch (build.task.sourceType) {
  | SourceType.Transient => withLock(build.lockPath, perform)
  | SourceType.Immutable => perform()
  };
};

let runCommand = (build, cmd) => {
  let env =
    switch (Bos.OS.Env.var("TERM")) {
    | Some(term) => Astring.String.Map.add("TERM", term, build.env)
    | None => build.env
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
    let%bind exec = Sandbox.exec(~env, build.sandbox, cmd);
    Bos.OS.Cmd.(in_null |> exec(~err=Bos.OS.Cmd.err_run_out) |> out_stdout);
  };
  switch (runStatus) {
  | `Exited(0) => Ok()
  | status => Error(`CommandError((cmd, status)))
  };
};

let runCommandInteractive = (build, cmd) => {
  let env =
    switch (Bos.OS.Env.var("TERM")) {
    | Some(term) => Astring.String.Map.add("TERM", term, build.env)
    | None => build.env
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
    let%bind exec = Sandbox.exec(~env, build.sandbox, cmd);
    Bos.OS.Cmd.(in_stdin |> exec(~err=Bos.OS.Cmd.err_stderr) |> out_stdout);
  };
  switch (runStatus) {
  | `Exited(0) => Ok()
  | status => Error(`CommandError((cmd, status)))
  };
};

let build = (~buildOnly=true, ~force=false, ~cfg: Config.t, task: Task.t) => {
  let%bind (build, lifecycle) = configureBuild(~cfg, task);
  Logs.debug(m => m("start %s", build.task.id));
  let (module Lifecycle): (module LIFECYCLE) = lifecycle;
  let performBuild = sourceModTime => {
    Logs.debug(m => m("building"));
    Logs.app(m =>
      m(
        "# esy-build-package: building: %s@%s",
        build.task.name,
        build.task.version,
      )
    );

    let runBuildAndInstall = (build: build) => {
      let runEsyInstaller = installFilenames => {
        let rootPath = Lifecycle.getRootPath(build);
        let findInstallFilenames = () => {
          let%bind items = Run.ls(rootPath);
          return(
            items
            |> List.filter(name => Path.has_ext(".install", name))
            |> List.map(name => Path.basename(name)),
          );
        };
        switch (installFilenames) {
        /* the case where esy-installer is called implicitly, ignore the case
         * we have no *.install files */
        | None =>
          switch%bind (findInstallFilenames()) {
          | [] => ok
          | [installFilename] =>
            install(
              ~prefixPath=build.stagePath,
              ~rootPath,
              ~installFilename,
              (),
            )
          | _ => error("multiple *.install files found")
          }
        /* the case where esy-installer is called explicitly with 0 args, fail
         * on all but a single *.install file found. */
        | Some([]) =>
          switch%bind (findInstallFilenames()) {
          | [] => error("no *.install files found")
          | [installFilename] =>
            install(
              ~prefixPath=build.stagePath,
              ~rootPath,
              ~installFilename,
              (),
            )
          | _ => error("multiple *.install files found")
          }
        | Some(installFilenames) =>
          let f = ((), installFilename) =>
            install(
              ~prefixPath=build.stagePath,
              ~rootPath,
              ~installFilename,
              (),
            );
          EsyLib.Result.List.foldLeft(~f, ~init=(), installFilenames);
        };
      };

      let runCommand = cmd => {
        ();
        switch (Cmd.to_list(cmd)) {
        | [] => error("empty command")
        | ["esy-installer", ...installFilenames] =>
          runEsyInstaller(Some(installFilenames))
        | _ => runCommand(build, cmd)
        };
      };

      let runCommands = cmds => {
        let rec aux = cmds =>
          switch (cmds) {
          | [] => Ok()
          | [cmd, ...cmds] =>
            Logs.app(m =>
              m("# esy-build-package: running: %s", Cmd.to_string(cmd))
            );
            let%bind () = runCommand(cmd);
            aux(cmds);
          };
        aux(cmds);
      };

      let runBuild = () => runCommands(build.build);

      let runInstall = () =>
        switch (build.install) {
        | [] => runEsyInstaller(None)
        | commands => runCommands(commands)
        };

      let%bind () = runBuild();
      let%bind () =
        if (! buildOnly) {
          runInstall();
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
        switch (sourceModTime, build.task.sourceType) {
        | (None, SourceType.Transient) =>
          if (isRoot(build)) {
            Ok(None);
          } else {
            Logs.debug(m => m("computing build mtime"));
            let%bind v = findSourceModTime(build);
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
    BuildInfo.toFile(build.infoPath, info);
  };
  switch (force, build.task.sourceType) {
  | (true, _) =>
    Logs.debug(m => m("forcing build"));
    performBuild(None);
  | (false, SourceType.Transient) =>
    if (isRoot(build)) {
      performBuild(None);
    } else {
      Logs.debug(m => m("checking for staleness"));
      let%bind info = BuildInfo.ofFile(build.infoPath);
      let prevSourceModTime =
        Option.bind(~f=v => v.BuildInfo.sourceModTime, info);
      let%bind sourceModTime = findSourceModTime(build);
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
    let%bind installPathExists = exists(build.installPath);
    if (installPathExists) {
      Logs.debug(m => m("build exists in store, skipping"));
      ok;
    } else {
      performBuild(None);
    };
  };
};
