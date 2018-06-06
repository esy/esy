open EsyInstaller;

module Api = {
  let solve = (cfg: Config.t) =>
    RunAsync.Syntax.(
      {
        let%bind manifest =
          PackageJson.ofFile(Path.(cfg.basePath / "package.json"));
        let%bind pkg =
          RunAsync.ofRun(
            Package.make(
              ~version=Solution.Version.LocalPath(cfg.basePath),
              Package.PackageJson(manifest),
            ),
          );
        let%bind solution = Solve.solve(~cfg, pkg);
        Solution.toFile(cfg.lockfilePath, solution);
      }
    );

  let fetch = (cfg: Config.t) =>
    RunAsync.Syntax.(
      {
        let%bind () = Fs.rmPath(Path.(cfg.basePath / "node_modules"));
        let%bind solution = Solution.ofFile(cfg.lockfilePath);
        Fetch.fetch(cfg, solution);
      }
    );

  let solveAndFetch = (cfg: Config.t) =>
    RunAsync.Syntax.(
      if%bind (Fs.exists(cfg.lockfilePath)) {
        fetch(cfg);
      } else {
        let%bind () = solve(cfg);
        fetch(cfg);
      }
    );

  let importOpam =
      (~path: Path.t, ~name: option(string), ~version: option(string), _cfg) => {
    open RunAsync.Syntax;

    let version =
      switch (version) {
      | Some(version) => OpamVersion.Version.parseExn(version)
      | None => OpamVersion.Version.parseExn("1.0.0")
      };

    let name =
      switch (name) {
      | Some(name) => "@opam/" ++ name
      | None => "@opam/unknown-opam-package"
      };

    let manifest = {
      let manifest =
        OpamFile.parseManifest(
          (name, version),
          OpamParser.file(Path.toString(path)),
        );
      OpamFile.{...manifest, source: Types.PendingSource.NoSource};
    };
    let (packageJson, _, _) =
      OpamFile.toPackageJson(manifest, Solution.Version.Opam(version));
    print_endline(Yojson.Safe.pretty_to_string(packageJson));
    return();
  };
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

  let sandboxPathArg = {
    let doc = "Specifies esy sandbox path.";
    let env = Arg.env_var("ESYI__SANDBOX", ~doc);
    Arg.(
      value
      & opt(some(Cli.pathConv), None)
      & info(["sandbox-path", "S"], ~env, ~docs, ~doc)
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

  let cfgTerm = {
    let parse = (cachePath, sandboxPath, npmRegistry, ()) => {
      let sandboxPath =
        switch (sandboxPath) {
        | Some(sandboxPath) => sandboxPath
        | None => cwd
        };
      Config.make(~cachePath?, ~npmRegistry?, sandboxPath);
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

  let runWithConfig = (f, cfg) => {
    let cfg = Lwt_main.run(cfg);
    switch (cfg) {
    | Ok(cfg) => run(f(cfg))
    | Error(err) => `Error((false, Run.formatError(err)))
    };
  };

  let defaultCommand = {
    let doc = "Dependency installer";
    let info = Term.info("esyi", ~version, ~doc, ~sdocs, ~exits);
    let cmd = cfg => Api.solveAndFetch(cfg);
    (Term.(ret(const(runWithConfig(cmd)) $ cfgTerm)), info);
  };

  let installCommand = {
    let doc = "Solve & fetch dependencies";
    let info = Term.info("install", ~version, ~doc, ~sdocs, ~exits);
    let cmd = cfg => Api.solveAndFetch(cfg);
    (Term.(ret(const(runWithConfig(cmd)) $ cfgTerm)), info);
  };

  let solveCommand = {
    let doc = "Solve dependencies and store the solution as a lockfile";
    let info = Term.info("solve", ~version, ~doc, ~sdocs, ~exits);
    let cmd = cfg => Api.solve(cfg);
    (Term.(ret(const(runWithConfig(cmd)) $ cfgTerm)), info);
  };

  let fetchCommand = {
    let doc = "Fetch dependencies using the solution in a lockfile";
    let info = Term.info("fetch", ~version, ~doc, ~sdocs, ~exits);
    let cmd = cfg => Api.fetch(cfg);
    (Term.(ret(const(runWithConfig(cmd)) $ cfgTerm)), info);
  };

  let opamImportCommand = {
    let doc = "Import opam file";
    let info = Term.info("import-opam", ~version, ~doc, ~sdocs, ~exits);
    let cmd = (cfg, name, version, path) =>
      run(Api.importOpam(~path, ~name, ~version, cfg));
    let nameTerm = {
      let doc = "Name of the opam package";
      Arg.(
        value & opt(some(string), None) & info(["opam-name"], ~docs, ~doc)
      );
    };
    let versionTerm = {
      let doc = "Version of the opam package";
      Arg.(
        value
        & opt(some(string), None)
        & info(["opam-version"], ~docs, ~doc)
      );
    };
    let pathTerm = {
      let doc = "Path to the opam file.";
      Arg.(
        required & pos(0, some(Cli.pathConv), None) & info([], ~docs, ~doc)
      );
    };
    (
      Term.(ret(const(cmd) $ cfgTerm $ nameTerm $ versionTerm $ pathTerm)),
      info,
    );
  };

  let commands = [
    installCommand,
    solveCommand,
    fetchCommand,
    opamImportCommand,
  ];

  let run = () => {
    Printexc.record_backtrace(true);
    Term.(exit(eval_choice(~argv=Sys.argv, defaultCommand, commands)));
  };
};

let () = CommandLineInterface.run();
