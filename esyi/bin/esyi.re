open EsyInstaller;
module String = Astring.String;

module Api = {
  let solve = (cfg: Config.t) =>
    RunAsync.Syntax.(
      {
        let%bind manifest = Manifest.Root.ofDir(cfg.basePath);
        let%bind root =
          Manifest.toPackage(
            ~version=
              Package.Version.Source(Package.Source.LocalPath(cfg.basePath)),
            manifest.manifest,
          );
        let%bind solution =
          Solver.solve(~cfg, ~resolutions=manifest.resolutions, root);
        Solution.LockfileV1.toFile(
          ~cfg,
          ~manifest,
          ~solution,
          cfg.lockfilePath,
        );
      }
    );

  let fetch = (cfg: Config.t) =>
    RunAsync.Syntax.(
      {
        let%bind manifest = Manifest.Root.ofDir(cfg.basePath);
        switch%bind (
          Solution.LockfileV1.ofFile(~cfg, ~manifest, cfg.lockfilePath)
        ) {
        | Some(solution) =>
          let%bind () = Fs.rmPath(Path.(cfg.basePath / "node_modules"));
          Fetch.fetch(~cfg, solution);
        | None => error("no lockfile found, run 'esyi solve' first")
        };
      }
    );

  let printCudfUniverse = (cfg: Config.t) =>
    RunAsync.Syntax.(
      {
        let%bind manifest = Manifest.Root.ofDir(cfg.basePath);
        let%bind root =
          Manifest.toPackage(
            ~version=
              Package.Version.Source(Package.Source.LocalPath(cfg.basePath)),
            manifest.Manifest.Root.manifest,
          );
        let%bind solver =
          Solver.make(
            ~cfg,
            ~resolutions=manifest.Manifest.Root.resolutions,
            (),
          );
        let%bind solver =
          Solver.add(~dependencies=root.Package.dependencies, solver);
        let (cudfUniverse, _) = Universe.toCudf(solver.Solver.universe);
        Cudf_printer.pp_universe(stdout, cudfUniverse);
        return();
      }
    );

  let solveAndFetch = (cfg: Config.t) =>
    RunAsync.Syntax.(
      {
        let%bind manifest = Manifest.Root.ofDir(cfg.basePath);
        switch%bind (
          Solution.LockfileV1.ofFile(~cfg, ~manifest, cfg.lockfilePath)
        ) {
        | Some(solution) =>
          if%bind (Fetch.isInstalled(~cfg, solution)) {
            return();
          } else {
            fetch(cfg);
          }
        | None =>
          let%bind () = solve(cfg);
          fetch(cfg);
        };
      }
    );
  /* let importOpam = */
  /*     (~path: Path.t, ~name: option(string), ~version: option(string), _cfg) => { */
  /*   open RunAsync.Syntax; */
  /*   let version = */
  /*     switch (version) { */
  /*     | Some(version) => OpamVersion.Version.parseExn(version) */
  /*     | None => OpamVersion.Version.parseExn("1.0.0") */
  /*     }; */
  /*   let%bind name = */
  /*     RunAsync.ofRun( */
  /*       switch (name) { */
  /*       | Some(name) => OpamManifest.PackageName.ofNpm("@opam/" ++ name) */
  /*       | None => OpamManifest.PackageName.ofNpm("@opam/unknown-opam-package") */
  /*       }, */
  /*     ); */
  /*   let%bind manifest = { */
  /*     let%bind manifest = */
  /*       OpamManifest.runParsePath( */
  /*         ~parser=OpamManifest.parseManifest(~name, ~version), */
  /*         path, */
  /*       ); */
  /*     return(OpamManifest.{...manifest, source: Package.Source.NoSource}); */
  /*   }; */
  /*   let {Package.OpamInfo.packageJson, _} = */
  /*     OpamManifest.toPackageJson(manifest, Package.Version.Opam(version)); */
  /*   print_endline(Yojson.Safe.pretty_to_string(packageJson)); */
  /*   return(); */
  /* }; */
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

  let cfgTerm = {
    let parse =
        (
          cachePath,
          sandboxPath,
          opamRepository,
          esyOpamOverride,
          npmRegistry,
          solveTimeout,
          (),
        ) => {
      open RunAsync.Syntax;
      let sandboxPath =
        switch (sandboxPath) {
        | Some(sandboxPath) => sandboxPath
        | None => cwd
        };
      let%bind esySolveCmd =
        resolve("esy-solve-cudf/esySolveCudfCommand.exe");
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
      Config.make(
        ~esySolveCmd,
        ~createProgressReporter,
        ~cachePath?,
        ~npmRegistry?,
        ~opamRepository?,
        ~esyOpamOverride?,
        ~solveTimeout?,
        sandboxPath,
      );
    };
    Term.(
      const(parse)
      $ cachePathArg
      $ sandboxPathArg
      $ opamRepositoryArg
      $ esyOpamOverrideArg
      $ npmRegistryArg
      $ solveTimeoutArg
      $ Cli.setupLogTerm
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

  let printCudfUniverse = {
    let doc = "Print CUDF universe on stdout";
    let info =
      Term.info("print-cudf-universe", ~version, ~doc, ~sdocs, ~exits);
    let cmd = cfg => Api.printCudfUniverse(cfg);
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

  /* let opamImportCommand = { */
  /*   let doc = "Import opam file"; */
  /*   let info = Term.info("import-opam", ~version, ~doc, ~sdocs, ~exits); */
  /*   let cmd = (cfg, name, version, path) => */
  /*     run(Api.importOpam(~path, ~name, ~version, cfg)); */
  /*   let nameTerm = { */
  /*     let doc = "Name of the opam package"; */
  /*     Arg.( */
  /*       value & opt(some(string), None) & info(["opam-name"], ~docs, ~doc) */
  /*     ); */
  /*   }; */
  /*   let versionTerm = { */
  /*     let doc = "Version of the opam package"; */
  /*     Arg.( */
  /*       value */
  /*       & opt(some(string), None) */
  /*       & info(["opam-version"], ~docs, ~doc) */
  /*     ); */
  /*   }; */
  /*   let pathTerm = { */
  /*     let doc = "Path to the opam file."; */
  /*     Arg.( */
  /*       required & pos(0, some(Cli.pathConv), None) & info([], ~docs, ~doc) */
  /*     ); */
  /*   }; */
  /*   ( */
  /*     Term.(ret(const(cmd) $ cfgTerm $ nameTerm $ versionTerm $ pathTerm)), */
  /*     info, */
  /*   ); */
  /* }; */

  let commands = [
    installCommand,
    solveCommand,
    fetchCommand,
    /* opamImportCommand, */
    printCudfUniverse,
  ];

  let run = () => {
    Printexc.record_backtrace(true);
    Term.(exit(Cli.eval(~defaultCommand, ~commands, ())));
  };
};

let () = CommandLineInterface.run();
