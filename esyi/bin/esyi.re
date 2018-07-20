open EsyInstaller;
module String = Astring.String;

module Api = {
  let lockfilePath = (sandbox: Sandbox.t) =>
    Path.(sandbox.path / "esyi.lock.json");

  let solve = (sandbox: Sandbox.t) =>
    RunAsync.Syntax.(
      {
        let%bind solution = Solver.solve(sandbox);
        Solution.LockfileV1.toFile(
          ~sandbox,
          ~solution,
          lockfilePath(sandbox),
        );
      }
    );

  let fetch = (sandbox: Sandbox.t) =>
    RunAsync.Syntax.(
      switch%bind (
        Solution.LockfileV1.ofFile(~sandbox, lockfilePath(sandbox))
      ) {
      | Some(solution) =>
        let%bind () = Fs.rmPath(Path.(sandbox.Sandbox.path / "node_modules"));
        Fetch.fetch(~sandbox, solution);
      | None => error("no lockfile found, run 'esyi solve' first")
      }
    );

  let printCudfUniverse = (sandbox: Sandbox.t) =>
    RunAsync.Syntax.(
      {
        let%bind solver =
          Solver.make(
            ~cfg=sandbox.cfg,
            ~resolutions=sandbox.Sandbox.resolutions,
            (),
          );
        let%bind (solver, _) =
          Solver.add(~dependencies=sandbox.root.Package.dependencies, solver);
        let (cudfUniverse, _) = Universe.toCudf(solver.Solver.universe);
        Cudf_printer.pp_universe(stdout, cudfUniverse);
        return();
      }
    );

  let solveAndFetch = (sandbox: Sandbox.t) =>
    RunAsync.Syntax.(
      switch%bind (
        Solution.LockfileV1.ofFile(~sandbox, lockfilePath(sandbox))
      ) {
      | Some(solution) =>
        if%bind (Fetch.isInstalled(~sandbox, solution)) {
          return();
        } else {
          fetch(sandbox);
        }
      | None =>
        let%bind () = solve(sandbox);
        fetch(sandbox);
      }
    );
};

module CommandLineInterface = {
  open Cmdliner;

  let exits = Term.default_exits;
  let docs = Manpage.s_common_options;
  let sdocs = Manpage.s_common_options;

  let cwd = Path.v(Sys.getcwd());
  let version = "0.1.0";

  let resolve = req => {
    open RunAsync.Syntax;
    let currentExecutable = Path.v(Sys.executable_name);
    let%bind currentFilename = Fs.realpath(currentExecutable);
    let currentDirname = Path.parent(currentFilename);
    let p =
      Run.ofBosError(EsyLib.NodeResolution.resolve(req, currentDirname));
    switch (p) {
    | Ok(Some(p)) => return(Cmd.v(Path.toString(p)))
    | Ok(None) => error("not found: " ++ req)
    | Error(err) => error(Run.formatError(err))
    };
  };

  let checkoutConv = {
    let parse = v =>
      switch (String.cut(~sep=":", v)) {
      | Some((remote, "")) => Ok(`Remote(remote))
      | Some(("", local)) => Ok(`Local(Path.v(local)))
      | Some((remote, local)) => Ok(`RemoteLocal((remote, Path.v(local))))
      | None => Ok(`Remote(v))
      };
    let print = (fmt: Format.formatter, v) =>
      switch (v) {
      | `RemoteLocal(remote, local) =>
        Fmt.pf(fmt, "%s:%s", remote, Path.toString(local))
      | `Local(local) => Fmt.pf(fmt, ":%s", Path.toString(local))
      | `Remote(remote) => Fmt.pf(fmt, "%s", remote)
      };
    Arg.conv(~docv="VAL", (parse, print));
  };

  let opamRepositoryArg = {
    let doc = "Specifies an opam repository to use.";
    let docv = "REMOTE[:LOCAL]";
    let env = Arg.env_var("ESYI__OPAM_REPOSITORY", ~doc);
    Arg.(
      value
      & opt(some(checkoutConv), None)
      & info(["opam-repository"], ~env, ~docs, ~doc, ~docv)
    );
  };

  let esyOpamOverrideArg = {
    let doc = "Specifies an opam override repository to use.";
    let docv = "REMOTE[:LOCAL]";
    let env = Arg.env_var("ESYI__OPAM_OVERRIDE", ~doc);
    Arg.(
      value
      & opt(some(checkoutConv), None)
      & info(["opam-override-repository"], ~env, ~docs, ~doc, ~docv)
    );
  };

  let sandboxPathArg = {
    let doc = "Specifies esy sandbox path.";
    let env = Arg.env_var("ESYI__SANDBOX", ~doc);
    Arg.(
      value
      & opt(some(Cli.pathConv), None)
      & info(["sandbox-path", "S"], ~env, ~docs, ~doc)
    );
  };

  let cacheTarballsPath = {
    let doc = "Specifies tarballs cache directory.";
    Arg.(
      value
      & opt(some(Cli.pathConv), None)
      & info(["cache-tarballs-path"], ~docs, ~doc)
    );
  };

  let cachePathArg = {
    let doc = "Specifies cache directory..";
    let env = Arg.env_var("ESYI__CACHE", ~doc);
    Arg.(
      value
      & opt(some(Cli.pathConv), None)
      & info(["cache-path"], ~env, ~docs, ~doc)
    );
  };

  let npmRegistryArg = {
    let doc = "Specifies npm registry to use.";
    let env = Arg.env_var("NPM_CONFIG_REGISTRY", ~doc);
    Arg.(
      value
      & opt(some(string), None)
      & info(["npm-registry"], ~env, ~docs, ~doc)
    );
  };

  let solveTimeoutArg = {
    let doc = "Specifies timeout for running depsolver.";
    Arg.(
      value & opt(some(float), None) & info(["solve-timeout"], ~docs, ~doc)
    );
  };

  let skipRepositoryUpdateArg = {
    let doc = "Skip updating opam-repository and esy-opam-overrides repositories.";
    Arg.(value & flag & info(["skip-repository-update"], ~docs, ~doc));
  };

  let sandboxTerm = {
    let parse =
        (
          cachePath,
          cacheTarballsPath,
          sandboxPath,
          opamRepository,
          esyOpamOverride,
          npmRegistry,
          solveTimeout,
          skipRepositoryUpdate,
          (),
        ) => {
      open RunAsync.Syntax;

      let sandboxPath =
        switch (sandboxPath) {
        | Some(sandboxPath) => sandboxPath
        | None => cwd
        };

      let createProgressReporter = (~name, ()) => {
        let progress = msg => {
          let status = Format.asprintf(".... %s %s", name, msg);
          Cli.Progress.setStatus(status);
        };
        let finish = () => {
          let%lwt () = Cli.Progress.clearStatus();
          Logs_lwt.app(m => m("%s: done", name));
        };
        (progress, finish);
      };
      let%bind esySolveCmd =
        resolve("esy-solve-cudf/esySolveCudfCommand.exe");
      let%bind cfg =
        Config.make(
          ~esySolveCmd,
          ~createProgressReporter,
          ~cachePath?,
          ~cacheTarballsPath?,
          ~npmRegistry?,
          ~opamRepository?,
          ~esyOpamOverride?,
          ~solveTimeout?,
          ~skipRepositoryUpdate,
          (),
        );
      Sandbox.ofDir(~cfg, sandboxPath);
    };
    Term.(
      const(parse)
      $ cachePathArg
      $ cacheTarballsPath
      $ sandboxPathArg
      $ opamRepositoryArg
      $ esyOpamOverrideArg
      $ npmRegistryArg
      $ solveTimeoutArg
      $ skipRepositoryUpdateArg
      $ Cli.setupLogTerm
    );
  };

  let run = v => {
    let result =
      switch (Lwt_main.run(v)) {
      | Ok () => `Ok()
      | Error(err) => `Error((false, Run.formatError(err)))
      };
    Lwt_main.run(Cli.Progress.clearStatus());
    result;
  };

  let runWithSandbox = (f, sandbox) => {
    let sandbox = Lwt_main.run(sandbox);
    switch (sandbox) {
    | Ok(sandbox) => run(f(sandbox))
    | Error(err) => `Error((false, Run.formatError(err)))
    };
  };

  let defaultCommand = {
    let doc = "Dependency installer";
    let info = Term.info("esyi", ~version, ~doc, ~sdocs, ~exits);
    let cmd = sandbox => Api.solveAndFetch(sandbox);
    (Term.(ret(const(runWithSandbox(cmd)) $ sandboxTerm)), info);
  };

  let printCudfUniverse = {
    let doc = "Print CUDF universe on stdout";
    let info =
      Term.info("print-cudf-universe", ~version, ~doc, ~sdocs, ~exits);
    let cmd = sandbox => Api.printCudfUniverse(sandbox);
    (Term.(ret(const(runWithSandbox(cmd)) $ sandboxTerm)), info);
  };

  let installCommand = {
    let doc = "Solve & fetch dependencies";
    let info = Term.info("install", ~version, ~doc, ~sdocs, ~exits);
    let cmd = cfg => Api.solveAndFetch(cfg);
    (Term.(ret(const(runWithSandbox(cmd)) $ sandboxTerm)), info);
  };

  let solveCommand = {
    let doc = "Solve dependencies and store the solution as a lockfile";
    let info = Term.info("solve", ~version, ~doc, ~sdocs, ~exits);
    let cmd = cfg => Api.solve(cfg);
    (Term.(ret(const(runWithSandbox(cmd)) $ sandboxTerm)), info);
  };

  let fetchCommand = {
    let doc = "Fetch dependencies using the solution in a lockfile";
    let info = Term.info("fetch", ~version, ~doc, ~sdocs, ~exits);
    let cmd = cfg => Api.fetch(cfg);
    (Term.(ret(const(runWithSandbox(cmd)) $ sandboxTerm)), info);
  };

  let commands = [
    installCommand,
    solveCommand,
    fetchCommand,
    printCudfUniverse,
  ];

  let run = () => {
    Printexc.record_backtrace(true);
    Term.(exit(eval_choice(~argv=Sys.argv, defaultCommand, commands)));
  };
};

let () = CommandLineInterface.run();
