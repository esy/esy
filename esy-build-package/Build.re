module EsyBash = EsyLib.EsyBash;
module Path = EsyLib.Path;
module Option = EsyLib.Option;
module System = EsyLib.System;
open Run;

type t = {
  plan: Plan.t,
  sourcePath: Path.t,
  storePath: Path.t,
  lockPath: Path.t,
  env: Bos.OS.Env.t,
  build: list(Cmd.t),
  install: list(Cmd.t),
  sandbox: Sandbox.sandbox,
};

type build = t;

let isRoot = (build: t) =>
  Config.Value.compare(build.plan.sourcePath, Config.Value.project) == 0;

let regex = (base, segments) => {
  let pat = String.concat(Path.dirSep, [Path.show(base), ...segments]);
  Sandbox.Regex(pat);
};

module type LIFECYCLE = {
  let rootPath: build => Path.t;
  let buildPath: build => Path.t;
  let stagePath: build => Path.t;
  let installPath: build => Path.t;

  let getAllowedToWritePaths: (Plan.t, Path.t) => list(Sandbox.pattern);
  let prepare: build => Run.t(unit, _);
  let finalize: build => Run.t(unit, _);
};

/*

   A lifecycle of a build which is performed in its original source tree and
   adheres to all esy convention (most importantly uses $cur__target_dir for its
   build dir).

 */
module OutOfSourceLifecycle: LIFECYCLE = {
  let rootPath = build => build.sourcePath;
  let buildPath = build =>
    Path.(build.storePath / EsyLib.Store.buildTree / build.plan.id);
  let stagePath = build =>
    Path.(build.storePath / EsyLib.Store.stageTree / build.plan.id);
  let installPath = build =>
    Path.(build.storePath / EsyLib.Store.installTree / build.plan.id);

  let getAllowedToWritePaths = (_task, _sourcePath) => [];
  let prepare = _build => ok;
  let finalize = _build => ok;
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
  let rootPath = build =>
    Path.(build.storePath / EsyLib.Store.buildTree / build.plan.id);
  let buildPath = build =>
    Path.(build.storePath / EsyLib.Store.buildTree / build.plan.id);
  let stagePath = build =>
    Path.(build.storePath / EsyLib.Store.stageTree / build.plan.id);
  let installPath = build =>
    Path.(build.storePath / EsyLib.Store.installTree / build.plan.id);

  let getAllowedToWritePaths = (_task, _sourcePath) => [];

  let prepare = (build: build) => {
    let%bind () = rm(buildPath(build));
    let%bind () = mkdir(buildPath(build));
    let%bind () = {
      let ignore = [
        ".git",
        ".hg",
        ".svn",
        "node_modules",
        "_esy",
        "_build",
        "_install",
        "_release",
        "_esybuild",
        "_esyinstall",
      ];
      copyContents(~from=build.sourcePath, ~ignore, buildPath(build));
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
  let rootPath = (build: build) => build.sourcePath;
  let buildPath = build =>
    Path.(build.storePath / EsyLib.Store.buildTree / build.plan.id);
  let stagePath = build =>
    Path.(build.storePath / EsyLib.Store.stageTree / build.plan.id);
  let installPath = build =>
    Path.(build.storePath / EsyLib.Store.installTree / build.plan.id);

  let getAllowedToWritePaths = (_task, sourcePath) =>
    Sandbox.[
      Subpath(Path.show(sourcePath / "_build")),
      regex(sourcePath, [".*", "[^/]*\\.install"]),
      regex(sourcePath, ["[^/]*\\.install"]),
      regex(sourcePath, [".*", "[^/]*\\.opam"]),
      regex(sourcePath, ["[^/]*\\.opam"]),
      regex(sourcePath, [".*", "jbuild-ignore"]),
    ];

  let prepareImpl = (build: build) => {
    let savedBuild = buildPath(build) / "_build";
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
    let savedBuild = buildPath(build) / "_build";
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
      let duneBuildDir = build.sourcePath / "_build";
      let%bind () =
        switch (lstat(duneBuildDir)) {
        | Ok({Unix.st_kind: S_DIR, _}) => ok
        | Ok(_) => rm(duneBuildDir)
        | Error(_) => ok
        };
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
  let rootPath = (build: build) => build.sourcePath;
  let buildPath = build =>
    Path.(build.storePath / EsyLib.Store.buildTree / build.plan.id);
  let stagePath = build =>
    Path.(build.storePath / EsyLib.Store.stageTree / build.plan.id);
  let installPath = build =>
    Path.(build.storePath / EsyLib.Store.installTree / build.plan.id);

  let getAllowedToWritePaths = (_task, sourcePath) =>
    Sandbox.[Subpath(Path.show(sourcePath))];

  let prepare = _build => ok;
  let finalize = _build => ok;
};

let configureBuild = (~cfg: Config.t, plan: Plan.t) => {
  let (module Lifecycle): (module LIFECYCLE) =
    switch (plan.buildType, plan.sourceType) {
    | (InSource, Immutable) => (module RelocateSourceLifecycle)
    | (InSource, ImmutableWithTransientDependencies) =>
      (module RelocateSourceLifecycle)
    | (InSource, Transient) => (module RelocateSourceLifecycle)

    | (JbuilderLike, Immutable) => (module RelocateSourceLifecycle)
    | (JbuilderLike, ImmutableWithTransientDependencies) =>
      (module RelocateSourceLifecycle)
    | (JbuilderLike, Transient) => (module JBuilderLifecycle)

    | (OutOfSource, Immutable) => (module OutOfSourceLifecycle)
    | (OutOfSource, ImmutableWithTransientDependencies) =>
      (module OutOfSourceLifecycle)
    | (OutOfSource, Transient) => (module OutOfSourceLifecycle)

    | (Unsafe, Immutable) => (module RelocateSourceLifecycle)
    | (Unsafe, ImmutableWithTransientDependencies) =>
      (module RelocateSourceLifecycle)
    | (Unsafe, Transient) => (module UnsafeLifecycle)
    };

  let%bind env = {
    let f = (k, v) =>
      fun
      | Ok(result) => {
          let v = Config.Value.render(cfg, v);
          Ok(Astring.String.Map.add(k, v, result));
        }
      | error => error;
    Astring.String.Map.fold(f, plan.env, Ok(Astring.String.Map.empty));
  };

  let renderCommands = (~cfg, cmds) => {
    let f = cmd => {
      let cmd = List.map(Config.Value.render(cfg), cmd);
      return(Cmd.of_list(cmd));
    };
    EsyLib.Result.List.map(~f, cmds);
  };
  let%bind install = renderCommands(~cfg, plan.install);
  let%bind build = renderCommands(~cfg, plan.build);

  let storePath =
    switch (plan.sourceType) {
    | Immutable => cfg.storePath
    | ImmutableWithTransientDependencies
    | Transient => cfg.localStorePath
    };

  let sourcePath = {
    let sourcePath = Config.Value.render(cfg, plan.sourcePath);
    Path.v(sourcePath);
  };
  let stagePath = Path.(storePath / EsyLib.Store.stageTree / plan.id);
  let buildPath = Path.(storePath / EsyLib.Store.buildTree / plan.id);
  let lockPath =
    Path.(storePath / EsyLib.Store.buildTree / plan.id |> addExt(".lock"));

  let%bind sandbox = {
    let%bind config = {
      let%bind tempPath = {
        let v = Path.v(Bos.OS.Env.opt_var("TMPDIR", ~absent="/tmp"));
        let%bind v = realpath(v);
        Ok(Path.show(v));
      };
      Ok({
        Sandbox.allowWrite: [
          regex(sourcePath, [".*", "\\.merlin"]),
          regex(sourcePath, ["\\.merlin"]),
          regex(sourcePath, [".*\\.install"]),
          regex(sourcePath, ["dune-project"]),
          Subpath(Path.show(buildPath)),
          Subpath(Path.show(stagePath)),
          Subpath("/private/tmp"),
          Subpath("/tmp"),
          Subpath(tempPath),
          ...Lifecycle.getAllowedToWritePaths(plan, sourcePath),
        ],
      });
    };
    Sandbox.init(config);
  };

  return((
    {plan, env, build, install, sourcePath, storePath, lockPath, sandbox},
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
      let stat = path =>
        switch (Run.lstatOrError(path)) {
        | Ok(stats) => Run.return(`Stats(stats))
        | Error((Unix.ENOENT, _call, _msg)) => Run.return(`DoesNotExist)
        | Error((errno, _call, _msg)) =>
          Run.errorf("stat %a: %s", Path.pp, path, Unix.error_message(errno))
        };
      let readdir = Run.ls;
      let mkdir = Run.mkdir;
    };
  });

let install = (~prefixPath, ~rootPath, ~installFilename=?, ()) => {
  let label =
    Fmt.(strf("esy-installer: %a", option(Path.pp), installFilename));
  EsyLib.Perf.measure(
    ~label,
    () => {
      Logs.app(m =>
        m("# esy-build-package: installing using built-in installer")
      );
      let res = Installer.run(~prefixPath, ~rootPath, installFilename);
      Run.coerceFromClosed(res);
    },
  );
};

let withLock = (lockPath: Path.t, f) => {
  let lockPath = Path.show(lockPath);
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

let commitBuildToStore = (build: build, lifecycle) => {
  let (module Lifecycle): (module LIFECYCLE) = lifecycle;
  let stagePath = Lifecycle.stagePath(build);
  let installPath = Lifecycle.installPath(build);
  let%bind () =
    write(
      ~data=Path.show(build.storePath),
      Path.(stagePath / "_esy" / "storePrefix"),
    );
  let%bind () = {
    let env = EsyLib.EsyBash.currentEnvWithMingwInPath;
    let%bind cmd =
      EsyLib.NodeResolution.resolve("./esyRewritePrefixCommand.exe");
    Bos.OS.Cmd.run(
      ~env,
      Cmd.(
        v(p(cmd))
        % "--orig-prefix"
        % p(stagePath)
        % "--dest-prefix"
        % p(installPath)
        % p(stagePath)
      ),
    );
  };
  let%bind () = mv(stagePath, installPath);
  ok;
};

let withBuild = (~commit=false, ~cfg: Config.t, plan: Plan.t, f) => {
  let%bind (build, lifecycle) = configureBuild(~cfg, plan);

  let (module Lifecycle): (module LIFECYCLE) = lifecycle;

  let buildPath = Lifecycle.buildPath(build);
  let stagePath = Lifecycle.stagePath(build);
  let installPath = Lifecycle.installPath(build);

  let initStoreAt = (path: Path.t) => {
    let%bind () = mkdir(Path.(path / "i"));
    let%bind () = mkdir(Path.(path / "b"));
    let%bind () = mkdir(Path.(path / "s"));
    Ok();
  };

  let%bind () = initStoreAt(cfg.storePath);
  let%bind () = initStoreAt(cfg.localStorePath);

  let perform = () => {
    let%bind () = rm(installPath);
    let%bind () = rm(stagePath);
    let%bind () = mkdir(stagePath);
    let%bind () = mkdir(stagePath / "bin");
    let%bind () = mkdir(stagePath / "lib");
    let%bind () = mkdir(stagePath / "etc");
    let%bind () = mkdir(stagePath / "sbin");
    let%bind () = mkdir(stagePath / "man");
    let%bind () = mkdir(stagePath / "share");
    let%bind () = mkdir(stagePath / "toplevel");
    let%bind () = mkdir(stagePath / "doc");
    let%bind () = mkdir(stagePath / "_esy");
    let%bind () = Lifecycle.prepare(build);
    let%bind () = mkdir(buildPath);
    let%bind () = mkdir(buildPath / "_esy");

    let rootPath = Lifecycle.rootPath(build);

    let%bind () =
      switch (withCwd(rootPath, ~f=() => f(build))) {
      | Ok () =>
        let%bind () =
          if (commit) {
            commitBuildToStore(build, (module Lifecycle));
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

  switch (build.plan.sourceType) {
  | Transient
  | ImmutableWithTransientDependencies => withLock(build.lockPath, perform)
  | Immutable => perform()
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
    | Some(path) => String.split_on_char(System.Environment.sep().[0], path)
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
    | Some(path) => String.split_on_char(System.Environment.sep().[0], path)
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

let build = (~buildOnly=true, ~cfg: Config.t, plan: Plan.t) => {
  let%bind (build, lifecycle) = configureBuild(~cfg, plan);
  Logs.debug(m => m("start %s", build.plan.id));
  let (module Lifecycle): (module LIFECYCLE) = lifecycle;

  let rootPath = Lifecycle.rootPath(build);
  let stagePath = Lifecycle.stagePath(build);

  Logs.debug(m => m("building"));
  Logs.app(m =>
    m(
      "# esy-build-package: building: %s@%s",
      build.plan.name,
      build.plan.version,
    )
  );
  Logs.app(m => m("# esy-build-package: pwd: %a", Fpath.pp, rootPath));

  let runBuildAndInstall = (build: build) => {
    let runEsyInstaller = installFilenames => {
      let findInstallFilenames = () => {
        let%bind items = Run.ls(rootPath);
        return(
          items
          |> List.filter(name => Path.hasExt(".install", name))
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
            ~prefixPath=stagePath,
            ~rootPath,
            ~installFilename=Path.v(installFilename),
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
            ~prefixPath=stagePath,
            ~rootPath,
            ~installFilename=Path.v(installFilename),
            (),
          )
        | _ => error("multiple *.install files found")
        }
      | Some(installFilenames) =>
        let f = ((), installFilename) =>
          install(
            ~prefixPath=stagePath,
            ~rootPath,
            ~installFilename=Path.v(installFilename),
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
      if (!buildOnly) {
        runInstall();
      } else {
        ok;
      };
    ok;
  };
  withBuild(~commit=!buildOnly, ~cfg, plan, runBuildAndInstall);
};
