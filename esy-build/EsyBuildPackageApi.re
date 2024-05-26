open EsyLib;

let run =
    (
      ~stdin=`Null,
      ~args=[],
      ~logPath=?,
      cfg: EsyBuildPackage.Config.t,
      action,
      plan: EsyBuildPackage.Plan.t,
    ) => {
  open RunAsync.Syntax;

  let* esyBuildPackageCmd = EsyRuntime.getEsyBuildPackageCommand();

  let action =
    switch (action) {
    | `Build => "build"
    | `Shell => "shell"
    | `Exec => "exec"
    };

  let runProcess = buildJsonFilename => {
    let* command =
      RunAsync.ofRun(
        Run.Syntax.(
          return(
            Cmd.(
              esyBuildPackageCmd
              % action
              % "--ocaml-pkg-name"
              % cfg.ocamlPkgName
              % "--ocaml-version"
              % cfg.ocamlVersion
              % "--global-store-prefix"
              % p(cfg.globalStorePrefix)
              % "--local-store-path"
              % p(cfg.localStorePath)
              % "--project-path"
              % p(cfg.projectPath)
              % "--plan"
              % p(buildJsonFilename)
              |> addArgs(args)
            ),
          )
        ),
      );

    let stdin =
      switch (stdin) {
      | `Null => `Dev_null
      | `Keep => `FD_copy(Unix.stdin)
      };

    let* (stdout, stderr, log) =
      switch (logPath) {
      | Some(logPath) =>
        let%lwt () =
          try%lwt(Fs.rmPathLwt(logPath)) {
          | _ => Lwt.return()
          };

        let* () = Fs.createDir(Path.parent(logPath));

        let%lwt fd =
          Lwt_unix.openfile(
            Path.show(logPath),
            Lwt_unix.[O_WRONLY, O_CREAT],
            0o644,
          );

        let fd = Lwt_unix.unix_file_descr(fd);
        return((`FD_copy(fd), `FD_copy(fd), Some((logPath, fd))));
      | None => return((`FD_copy(Unix.stdout), `FD_copy(Unix.stderr), None))
      };

    let waitForProcess = process => {
      let%lwt status = process#status;
      return((status, log));
    };

    ChildProcess.withProcess(
      ~env=
        ChildProcess.CurrentEnvOverride(
          Astring.String.Map.empty
          |> Astring.String.Map.add("_", Cmd.show(esyBuildPackageCmd)),
        ),
      ~stderr,
      ~stdout,
      ~stdin,
      command,
      waitForProcess,
    );
  };

  let buildJson = {
    let json = EsyBuildPackage.Plan.to_yojson(plan);
    Yojson.Safe.to_string(json);
  };

  Fs.withTempFile(~data=buildJson, runProcess);
};

let build =
    (~buildOnly=false, ~quiet=false, ~logPath=?, ~disableSandbox=?, cfg, plan) => {
  open RunAsync.Syntax;
  let args = {
    let addIf = (cond, arg, args) =>
      if (cond) {
        [arg, ...args];
      } else {
        args;
      };

    []
    |> addIf(buildOnly, "--build-only")
    |> addIf(quiet, "--quiet")
    |> addIf(
         switch (disableSandbox) {
         | Some(x) => x
         | None => false
         },
         "--disable-sandbox",
       );
  };

  let* (status, log) = run(~logPath?, ~args, cfg, `Build, plan);
  switch (status, log) {
  | (Unix.WEXITED(0), Some((_, fd))) =>
    UnixLabels.close(fd);
    return();
  | (Unix.WEXITED(0), None) => return()

  | (Unix.WEXITED(code), Some((logPath, fd)))
  | (Unix.WSIGNALED(code), Some((logPath, fd)))
  | (Unix.WSTOPPED(code), Some((logPath, fd))) =>
    UnixLabels.close(fd);
    let* log = Fs.readFile(logPath);
    Run.withContextOfLog(
      ~header="build log:",
      log,
      Run.errorf("build failed with exit code: %i", code),
    )
    |> RunAsync.ofRun;

  | (Unix.WEXITED(code), None)
  | (Unix.WSIGNALED(code), None)
  | (Unix.WSTOPPED(code), None) =>
    errorf("build failed with exit code: %i", code)
  };
};

let buildShell = (cfg, plan) => {
  open RunAsync.Syntax;
  let* (status, _log) = run(~stdin=`Keep, cfg, `Shell, plan);
  return(status);
};

let buildExec = (cfg, plan, cmd) => {
  open RunAsync.Syntax;
  let (tool, args) = Cmd.getToolAndArgs(cmd);
  let args = ["--", tool, ...args];
  let* (status, _log) = run(~stdin=`Keep, ~args, cfg, `Exec, plan);
  return(status);
};
