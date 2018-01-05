let relocateSourcePath = (config: Config.t, spec: BuildSpec.t) => {
  let cmd =
    Bos.Cmd.(
      empty
      % config.rsyncCmd
      % "--quiet"
      % "--archive"
      % "--exclude"
      % p(spec.buildPath)
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
      % (Path.to_string(spec.sourcePath) ++ "/")
      % p(spec.buildPath)
    );
  Bos.OS.Cmd.run(cmd);
};

let commitBuildToStore = (config: Config.t, spec: BuildSpec.t) => {
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
    switch stats.st_kind {
    | Unix.S_REG =>
      rewritePrefixInFile(
        ~origPrefix=spec.stagePath,
        ~destPrefix=spec.installPath,
        path
      )
    | Unix.S_LNK =>
      rewriteTargetInSymlink(
        ~origPrefix=spec.stagePath,
        ~destPrefix=spec.installPath,
        path
      )
    | _ => Ok()
    };
  let%bind () =
    Bos.OS.File.write(
      Path.(spec.stagePath / "_esy" / "storePrefix"),
      Path.to_string(config.storePath)
    );
  let%bind () = traverse(spec.stagePath, relocate);
  let%bind () = Bos.OS.Path.move(spec.stagePath, spec.installPath);
  ok;
};

let relocateBuildPath = (_config: Config.t, spec: BuildSpec.t) => {
  open Run;
  let savedBuild = spec.buildPath / "_build";
  let currentBuild = spec.sourcePath / "_build";
  let backupBuild = spec.sourcePath / "_build.prev";
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

let findSourceModTime = (spec: BuildSpec.t) => {
  open Run;
  let visit = (path: Path.t) =>
    fun
    | Ok(maxTime) =>
      if (path == spec.sourcePath) {
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
        }
    );
  Result.join(
    Bos.OS.Path.fold(
      ~dotfiles=true,
      ~traverse,
      visit,
      Ok(0.),
      [spec.sourcePath]
    )
  );
};

let doNothing = (_config: Config.t, _spec: BuildSpec.t) => Run.ok;

/**
 * Execute `run` within the build environment for `spec`.
 */
let withBuildEnv = (~commit=false, config: Config.t, spec: BuildSpec.t, f) => {
  open Run;
  let {BuildSpec.sourcePath, installPath, buildPath, stagePath, _} = spec;
  let (rootPath, prepareRootPath, completeRootPath) =
    switch (spec.buildType, spec.sourceType) {
    | (InSource, _) => (buildPath, relocateSourcePath, doNothing)
    | (JbuilderLike, Immutable) => (buildPath, relocateSourcePath, doNothing)
    | (JbuilderLike, Transient) =>
      let (start, commit) = relocateBuildPath(config, spec);
      (sourcePath, start, commit);
    | (JbuilderLike, Root) => (sourcePath, doNothing, doNothing)
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
      switch spec.buildType {
      | JbuilderLike => [
          Subpath(Path.to_string(sourcePath / "_build")),
          regex(sourcePath, [".*", "[^/]*\\.install"]),
          regex(sourcePath, ["[^/]*\\.install"]),
          regex(sourcePath, [".*", "[^/]*\\.opam"]),
          regex(sourcePath, ["[^/]*\\.opam"]),
          regex(sourcePath, [".*", "jbuild-ignore"])
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
        Subpath(tempPath)
      ]
    );
  };
  let env =
    switch (Bos.OS.Env.var("TERM")) {
    | Some(term) => Astring.String.Map.add("TERM", term, spec.env)
    | None => spec.env
    };
  let%bind exec = Sandbox.sandboxExec({allowWrite: sandboxConfig});
  let path =
    switch (Astring.String.Map.find("PATH", env)) {
    | Some(path) => String.split_on_char(':', path)
    | None => []
    };
  let run = cmd => {
    let%bind cmd = Cmd.resolveInvocation(path, cmd);
    Bos.OS.Cmd.(
      in_null |> exec(~err=Bos.OS.Cmd.err_run_out, ~env, cmd) |> to_stdout
    );
  };
  let runInteractive = cmd => {
    let%bind cmd = Cmd.resolveInvocation(path, cmd);
    Bos.OS.Cmd.(
      in_stdin |> exec(~err=Bos.OS.Cmd.err_stderr, ~env, cmd) |> to_stdout
    );
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
      switch (spec.sourceType, spec.buildType) {
      | (Immutable, _)
      | (_, InSource) =>
        let%bind () = rmdir(buildPath);
        let%bind () = mkdir(buildPath);
        ok;
      | _ =>
        let%bind () = mkdir(buildPath);
        ok;
      };
    let%bind () = prepareRootPath(config, spec);
    let%bind () = mkdir(buildPath / "_esy");
    ok;
  };
  /*
   * Finalize build/install.
   */
  let finalize = result =>
    switch result {
    | Ok () =>
      let%bind () =
        if (commit) {
          commitBuildToStore(config, spec);
        } else {
          ok;
        };
      let%bind () = completeRootPath(config, spec);
      ok;
    | error =>
      let%bind () = completeRootPath(config, spec);
      error;
    };
  let%bind () = Store.init(config.storePath);
  let%bind () = Store.init(config.localStorePath);
  let%bind () = prepare();
  let result = withCwd(rootPath, ~f=f(run, runInteractive));
  let%bind () = finalize(result);
  result;
};

let build =
    (~buildOnly=true, ~force=false, config: Config.t, spec: BuildSpec.t) => {
  open Run;
  Logs.debug(m => m("start %s", spec.id));
  let performBuild = sourceModTime => {
    Logs.debug(m => m("building"));
    let runBuildAndInstall = (run, _runInteractive, ()) => {
      let runList = cmds => {
        let rec _runList = cmds =>
          switch cmds {
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
      let {BuildSpec.build, install, _} = spec;
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
      withBuildEnv(~commit=! buildOnly, config, spec, runBuildAndInstall);
    let%bind info = {
      let%bind sourceModTime =
        switch (sourceModTime, spec.sourceType) {
        | (None, BuildSpec.Root)
        | (None, BuildSpec.Transient) =>
          let%bind v = findSourceModTime(spec);
          Ok(Some(v));
        | (v, _) => Ok(v)
        };
      Ok(
        BuildInfo.{sourceModTime, timeSpent: Unix.gettimeofday() -. startTime}
      );
    };
    BuildInfo.write(spec, info);
  };
  switch (force, spec.sourceType) {
  | (true, _) =>
    Logs.debug(m => m("forcing build"));
    performBuild(None);
  | (false, BuildSpec.Transient)
  | (false, BuildSpec.Root) =>
    Logs.debug(m => m("checking for staleness"));
    let info = BuildInfo.read(spec);
    let prevSourceModTime =
      Option.bind(~f=v => v.BuildInfo.sourceModTime, info);
    let%bind sourceModTime = findSourceModTime(spec);
    switch prevSourceModTime {
    | Some(prevSourceModTime) when sourceModTime > prevSourceModTime =>
      performBuild(Some(sourceModTime))
    | None => performBuild(Some(sourceModTime))
    | Some(_) =>
      Logs.debug(m => m("source code is not modified, skipping"));
      ok;
    };
  | (false, BuildSpec.Immutable) =>
    let%bind installPathExists = exists(spec.installPath);
    if (installPathExists) {
      Logs.debug(m => m("build exists in store, skipping"));
      ok;
    } else {
      performBuild(None);
    };
  };
};
