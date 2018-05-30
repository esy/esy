module Api = {
  let solve = (cfg: EsyInstaller.Config.t) => {
    let json =
      Yojson.Basic.from_file(
        Path.(cfg.basePath / "package.json" |> to_string),
      );
    let solution = EsyInstaller.Solve.solve(cfg, `PackageJson(json));
    EsyInstaller.Solution.toFile(cfg.lockfilePath, solution);
  };

  let fetch = (cfg: EsyInstaller.Config.t) =>
    RunAsync.Syntax.(
      {
        let%bind _ = Fs.rmPath(Path.(cfg.basePath / "node_modules"));
        let%bind solution = EsyInstaller.Solution.ofFile(cfg.lockfilePath);
        EsyInstaller.Fetch.fetch(cfg, solution);
      }
    );

  let solveAndFetch = (cfg: EsyInstaller.Config.t) =>
    RunAsync.Syntax.(
      if%bind (Fs.exists(cfg.lockfilePath)) {
        fetch(cfg);
      } else {
        let%bind () = solve(cfg);
        fetch(cfg);
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

  let setupLog = (style_renderer, level) => {
    Fmt_tty.setup_std_outputs(~style_renderer?, ());
    Logs.set_level(level);
    Logs.set_reporter(Logs_fmt.reporter());
    ();
  };

  let setupLogTerm =
    Term.(const(setupLog) $ Fmt_cli.style_renderer() $ Logs_cli.level());

  let pathConv = {
    let parse = Path.of_string;
    let print = Path.pp;
    Arg.conv(~docv="PATH", (parse, print));
  };

  let sandboxPathArg = {
    let doc = "Specifies esy sandbox path.";
    let env = Arg.env_var("ESYI__SANDBOX", ~doc);
    Arg.(
      value
      & opt(some(pathConv), None)
      & info(["sandbox-path", "S"], ~env, ~docs, ~doc)
    );
  };

  let cachePathArg = {
    let doc = "Specifies cache directory..";
    let env = Arg.env_var("ESYI__CACHE", ~doc);
    Arg.(
      value
      & opt(some(pathConv), None)
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

  let cfgTerm = {
    let parse = (cachePath, sandboxPath, npmRegistry, ()) => {
      let sandboxPath =
        switch (sandboxPath) {
        | Some(sandboxPath) => sandboxPath
        | None => cwd
        };
      EsyInstaller.Config.make(~cachePath?, ~npmRegistry?, sandboxPath);
    };
    Term.(
      const(parse)
      $ cachePathArg
      $ sandboxPathArg
      $ npmRegistryArg
      $ setupLogTerm
    );
  };

  let run = v =>
    switch (Lwt_main.run(v)) {
    | Ok () => `Ok()
    | Error(err) => `Error((false, Run.formatError(err)))
    };

  let defaultCommand = {
    let doc = "Dependency installer";
    let info = Term.info("esyi", ~version, ~doc, ~sdocs, ~exits);
    let cmd = cfg => run(Api.solveAndFetch(cfg));
    (Term.(ret(const(cmd) $ cfgTerm)), info);
  };

  let installCommand = {
    let doc = "Solve & fetch dependencies";
    let info = Term.info("install", ~version, ~doc, ~sdocs, ~exits);
    let cmd = cfg => run(Api.solveAndFetch(cfg));
    (Term.(ret(const(cmd) $ cfgTerm)), info);
  };

  let solveCommand = {
    let doc = "Solve dependencies and store the solution as a lockfile";
    let info = Term.info("solve", ~version, ~doc, ~sdocs, ~exits);
    let cmd = cfg => run(Api.solve(cfg));
    (Term.(ret(const(cmd) $ cfgTerm)), info);
  };

  let fetchCommand = {
    let doc = "Fetch dependencies using the solution in a lockfile";
    let info = Term.info("fetch", ~version, ~doc, ~sdocs, ~exits);
    let cmd = cfg => run(Api.fetch(cfg));
    (Term.(ret(const(cmd) $ cfgTerm)), info);
  };

  let commands = [installCommand, solveCommand, fetchCommand];

  let run = () => {
    Printexc.record_backtrace(true);
    Term.(exit(eval_choice(~argv=Sys.argv, defaultCommand, commands)));
  };
};

let () = CommandLineInterface.run();
