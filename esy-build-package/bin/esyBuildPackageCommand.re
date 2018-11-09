open EsyBuildPackage;
module Option = EsyLib.Option;
module File = Bos.OS.File;
module Dir = Bos.OS.Dir;

type verb =
  | Normal
  | Quiet
  | Verbose;

type commonOpts = {
  planPath: option(Fpath.t),
  buildPath: option(Fpath.t),
  storePath: option(Fpath.t),
  localStorePath: option(Fpath.t),
  projectPath: option(Fpath.t),
  logLevel: option(Logs.level),
};

let setupLog = (style_renderer, level) => {
  let style_renderer = Option.orDefault(~default=`None, style_renderer);
  Fmt_tty.setup_std_outputs(~style_renderer, ());
  Logs.set_level(level);
  Logs.set_reporter(Logs_fmt.reporter());
  level;
};

let createConfig = (copts: commonOpts) => {
  open Run;
  let {storePath, buildPath, localStorePath, projectPath, _} = copts;
  let%bind currentPath = Bos.OS.Dir.current();
  let projectPath = Option.orDefault(~default=currentPath, projectPath);
  Config.make(
    ~storePath?,
    ~buildPath=Option.orDefault(~default=projectPath / "_build", buildPath),
    ~localStorePath=
      Option.orDefault(~default=projectPath / "_store", localStorePath),
    ~projectPath,
    (),
  );
};

let build = (~buildOnly=false, ~force=false, copts: commonOpts) => {
  open Run;
  let {planPath, _} = copts;
  let planPath = Option.orDefault(~default=v("build.json"), planPath);
  let%bind cfg = createConfig(copts);
  let%bind plan = Plan.ofFile(planPath);
  let%bind () = Build.build(~buildOnly, ~force, ~cfg, plan);
  Ok();
};

let shell = (copts: commonOpts) => {
  open Run;
  let {planPath, _} = copts;
  let planPath = Option.orDefault(~default=v("build.json"), planPath);
  let%bind cfg = createConfig(copts);
  let%bind plan = Plan.ofFile(planPath);

  let ppBanner = (build: Build.t) => {
    open Fmt;

    let ppList = (ppItem, ppf, (title, items)) => {
      let pp =
        switch (items) {
        | [] => hbox(pair(string, unit(" <empty> ")))
        | items =>
          vbox(
            ~indent=2,
            pair(string, const(prefix(cut, vbox(list(ppItem))), items)),
          )
        };
      pp(ppf, (title, ()));
    };

    let ppBanner = (ppf, ()) => {
      Format.open_vbox(0);
      fmt("Package: %s@%s", ppf, plan.Plan.name, plan.Plan.version);
      Fmt.cut(ppf, ());
      Fmt.cut(ppf, ());
      ppList(Cmd.pp, ppf, ("Build Commands:", build.build));
      Fmt.cut(ppf, ());
      Fmt.cut(ppf, ());
      ppList(Cmd.pp, ppf, ("Install Commands:", build.install));
      Fmt.cut(ppf, ());
      Format.close_box();
    };

    Format.force_newline();
    ppBanner(Fmt.stdout, ());
    Format.force_newline();
    Format.print_flush();
  };

  let runShell = build => {
    ppBanner(build);
    let%bind rcFilename =
      createTmpFile(
        {|
        export PS1="[build $cur__name] % ";
        |},
      );
    let cmd =
      Cmd.of_list([
        "bash",
        "--noprofile",
        "--rcfile",
        Fpath.to_string(rcFilename),
      ]);
    Build.runCommandInteractive(build, cmd);
  };

  let%bind () = Build.withBuild(~cfg, plan, runShell);
  ok;
};

let exec = (copts, command) => {
  open Run;
  let {planPath, _} = copts;
  let planPath = Option.orDefault(~default=v("build.json"), planPath);
  let%bind cfg = createConfig(copts);
  let runCommand = build => {
    let cmd = Cmd.of_list(command);
    Build.runCommandInteractive(build, cmd);
  };
  let%bind plan = Plan.ofFile(planPath);
  let%bind () = Build.withBuild(~cfg, plan, runCommand);
  ok;
};

let runToCompletion = (~forceExitOnError=false, run) =>
  switch (run) {
  | Error(`Msg(msg)) => `Error((false, msg))
  | Error(`CommandError(cmd, status)) =>
    let exitCode =
      switch (status) {
      | `Exited(n) => n
      | `Signaled(n) => n
      };
    if (forceExitOnError) {
      exit(exitCode);
    } else {
      Format.fprintf(
        Format.err_formatter,
        "@[<h>error: command failed: %a (%a)@]@.",
        Cmd.pp,
        cmd,
        Bos.OS.Cmd.pp_status,
        status,
      );
      `Error((false, "exiting with errors above..."));
    };
  | _ => `Ok()
  };

let help = (_copts, man_format, cmds, topic) =>
  switch (topic) {
  | None => `Help((`Pager, None)) /* help about the program. */
  | Some(topic) =>
    let topics = ["topics", "patterns", "environment", ...cmds];
    let (conv, _) = Cmdliner.Arg.enum(List.rev_map(s => (s, s), topics));
    switch (conv(topic)) {
    | `Error(e) => `Error((false, e))
    | `Ok(t) when t == "topics" =>
      List.iter(print_endline, topics);
      `Ok();
    | `Ok(t) when List.mem(t, cmds) => `Help((man_format, Some(t)))
    | `Ok(_) =>
      let page = (
        (topic, 7, "", "", ""),
        [`S(topic), `P("Say something")],
      );
      `Ok(Cmdliner.Manpage.print(man_format, Format.std_formatter, page));
    };
  };

let () = {
  open Cmdliner;
  /* Help sections common to all commands */
  let help_secs = [
    `S(Manpage.s_common_options),
    `P("These options are common to all commands."),
    `S("MORE HELP"),
    `P("Use `$(mname) $(i,COMMAND) --help' for help on a single command."),
    `Noblank,
    `P("Use `$(mname) help patterns' for help on patch matching."),
    `Noblank,
    `P("Use `$(mname) help environment' for help on environment variables."),
    `S(Manpage.s_bugs),
    `P("Check bug reports at https://github.com/esy/esy."),
  ];
  /* Options common to all commands */
  let path = {
    let parse = Fpath.of_string;
    let print = Fpath.pp;
    Arg.conv(~docv="PATH", (parse, print));
  };
  let commonOptsT = {
    let docs = Manpage.s_common_options;
    let projectPath = {
      let doc = "Specifies esy project path.";
      let env = Arg.env_var("ESY__PROJECT_PATH", ~doc);
      Arg.(
        value
        & opt(some(path), None)
        & info(["project-path"], ~env, ~docs, ~docv="PATH", ~doc)
      );
    };
    let storePath = {
      let doc = "Specifies esy store path.";
      let env = Arg.env_var("ESY__STORE_PATH", ~doc);
      Arg.(
        value
        & opt(some(path), None)
        & info(["store-path"], ~env, ~docs, ~docv="PATH", ~doc)
      );
    };
    let localStorePath = {
      let doc = "Specifies esy sandbox path.";
      let env = Arg.env_var("ESY__LOCAL_STORE_PATH", ~doc);
      Arg.(
        value
        & opt(some(path), None)
        & info(["local-store-path"], ~env, ~docs, ~docv="PATH", ~doc)
      );
    };
    let buildPath = {
      let doc = "Specifies esy build path.";
      let env = Arg.env_var("ESY__BUILD_PATH", ~doc);
      Arg.(
        value
        & opt(some(path), None)
        & info(["build-path"], ~env, ~docs, ~docv="PATH", ~doc)
      );
    };
    let planPath = {
      let doc = "Specifies path to build plan.";
      let env = Arg.env_var("ESY__PLAN", ~doc);
      Arg.(
        value
        & opt(some(path), None)
        & info(["plan", "p"], ~env, ~docs, ~docv="PATH", ~doc)
      );
    };
    let setupLogT =
      Term.(
        const(setupLog)
        $ Fmt_cli.style_renderer()
        $ Logs_cli.level(~env=Arg.env_var("ESY__LOG"), ())
      );
    let parse =
        (
          projectPath,
          storePath,
          localStorePath,
          buildPath,
          planPath,
          logLevel,
        ) => {
      projectPath,
      storePath,
      localStorePath,
      buildPath,
      planPath,
      logLevel,
    };
    Term.(
      const(parse)
      $ projectPath
      $ storePath
      $ localStorePath
      $ buildPath
      $ planPath
      $ setupLogT
    );
  };
  /* Command terms */
  let default_cmd = {
    let doc = "esy package builder";
    let sdocs = Manpage.s_common_options;
    let exits = Term.default_exits;
    let man = help_secs;
    let cmd = opts => runToCompletion(build(opts));
    (
      Term.(ret(const(cmd) $ commonOptsT)),
      Term.info(
        "esy-build-package",
        ~version="v0.1.0",
        ~doc,
        ~sdocs,
        ~exits,
        ~man,
      ),
    );
  };
  let build_cmd = {
    let doc = "build package";
    let sdocs = Manpage.s_common_options;
    let exits = Term.default_exits;
    let man = help_secs;
    let cmd = (opts, buildOnly, force) =>
      runToCompletion(build(~buildOnly, ~force, opts));
    let forceT = {
      let doc = "Force build without running any staleness checks.";
      Arg.(value & flag & info(["f", "force"], ~doc));
    };
    let buildOnlyT = {
      let doc = "Only run build commands (skipping install commands).";
      Arg.(value & flag & info(["build-only"], ~doc));
    };
    (
      Term.(ret(const(cmd) $ commonOptsT $ buildOnlyT $ forceT)),
      Term.info("build", ~doc, ~sdocs, ~exits, ~man),
    );
  };
  let shell_cmd = {
    let doc = "shell into build environment";
    let sdocs = Manpage.s_common_options;
    let exits = Term.default_exits;
    let man = help_secs;
    let cmd = opts => runToCompletion(shell(opts));
    (
      Term.(ret(const(cmd) $ commonOptsT)),
      Term.info("shell", ~doc, ~sdocs, ~exits, ~man),
    );
  };
  let exec_cmd = {
    let doc = "execute command inside build environment";
    let sdocs = Manpage.s_common_options;
    let exits = Term.default_exits;
    let man = help_secs;
    let command_t =
      Arg.(non_empty & pos_all(string, []) & info([], ~docv="COMMAND"));
    let cmd = (opts, command) =>
      runToCompletion(~forceExitOnError=true, exec(opts, command));
    (
      Term.(ret(const(cmd) $ commonOptsT $ command_t)),
      Term.info("exec", ~doc, ~sdocs, ~exits, ~man),
    );
  };
  let help_cmd = {
    let topic = {
      let doc = "The topic to get help on. `topics' lists the topics.";
      Arg.(
        value & pos(0, some(string), None) & info([], ~docv="TOPIC", ~doc)
      );
    };
    let doc = "display help about esy-build-package and its commands";
    let man = [
      `S(Manpage.s_description),
      `P(
        "Prints help about esy-build-package commands and other subjects...",
      ),
      `Blocks(help_secs),
    ];
    (
      Term.(
        ret(
          const(help)
          $ commonOptsT
          $ Arg.man_format
          $ Term.choice_names
          $ topic,
        )
      ),
      Term.info("help", ~doc, ~exits=Term.default_exits, ~man),
    );
  };
  let cmds = [build_cmd, shell_cmd, exec_cmd, help_cmd];
  Term.(exit @@ eval_choice(default_cmd, cmds));
};
