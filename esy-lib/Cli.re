let isCi =
  switch (Sys.getenv_opt("CI")) {
  | Some(_) => true
  | None => false
  };

module ProgressReporter: {
  let status: unit => option(string);
  let setStatus: string => Lwt.t(unit);
  let clearStatus: unit => Lwt.t(unit);
} = {
  type t = {
    mutable status: option(string),
    statusLock: Lwt_mutex.t,
    enabled: bool,
  };

  let reporter = {
    let isatty = Unix.isatty(Unix.stderr);
    let enabled = !isCi && isatty;
    {
      status: None,
      statusLock: Lwt_mutex.create(),
      enabled,
    };
  };

  let hide = s =>
    switch (s) {
    | None => Lwt.return()
    | Some(s) =>
      let len = String.length(s);
      if (len > 0) {
        let s = Printf.sprintf("\r%*s\r", len, "");
        Lwt_io.write(Lwt_io.stderr, s);
      } else {
        Lwt.return();
      };
    };

  let show = s =>
    switch (s) {
    | Some(s) => Lwt_io.write(Lwt_io.stderr, s)
    | None => Lwt.return()
    };

  let status = () => reporter.status;

  let setStatus = status =>
    if (reporter.enabled) {
      Lwt_mutex.with_lock(
        reporter.statusLock,
        () => {
          let%lwt () = hide(reporter.status);
          reporter.status = Some(status);
          let%lwt () = show(reporter.status);
          let%lwt () = Lwt_io.flush(Lwt_io.stderr);
          Lwt.return();
        },
      );
    } else {
      Lwt.return();
    };

  let clearStatus = () =>
    if (reporter.enabled) {
      Lwt_mutex.with_lock(
        reporter.statusLock,
        () => {
          let%lwt () = hide(reporter.status);
          let%lwt () = Lwt_io.flush(Lwt_io.stderr);
          reporter.status = None;
          Lwt.return();
        },
      );
    } else {
      Lwt.return();
    };
};

let createProgressReporter = (~name, ()) => {
  let progress = fmt => {
    let kerr = _ => {
      let msg = Format.flush_str_formatter();
      ProgressReporter.setStatus(".... " ++ name ++ " " ++ msg);
    };

    Format.kfprintf(kerr, Format.str_formatter, fmt);
  };

  let finish = () => {
    let%lwt () = ProgressReporter.clearStatus();
    Logs_lwt.app(m =>
      m("%s: %s", name, <Pastel color=Pastel.Green> "done" </Pastel>)
    );
  };

  (progress, finish);
};

let pathConv = {
  open Cmdliner;
  let parse = Path.ofString;
  let print = Path.pp;
  Arg.conv(~docv="PATH", (parse, print));
};

let checkoutConv = {
  open Cmdliner;
  let parse = v => {
    switch (Astring.String.cut(~sep=":", v)) {
    | Some((remote, "")) => Ok(`Remote(remote))
    | Some(("", local)) => Ok(`Local(Path.v(local)))
    | Some((remote, local)) => Ok(`RemoteLocal((remote, Path.v(local))))
    | None => Ok(`Remote(v))
    };
  };

  let print = (fmt: Format.formatter, v) =>
    switch (v) {
    | `RemoteLocal(remote, local) =>
      Fmt.pf(fmt, "%s:%s", remote, Path.show(local))
    | `Local(local) => Fmt.pf(fmt, ":%s", Path.show(local))
    | `Remote(remote) => Fmt.pf(fmt, "%s", remote)
    };

  Arg.conv(~docv="VAL", (parse, print));
};

let cmdConv = {
  let parse = v => Ok(Cmd.v(v));
  let print = Cmd.pp;
  Cmdliner.Arg.conv(~docv="COMMAND", (parse, print));
};

let cmdTerm = (~doc, ~docv, makeconv) => {
  let commandTerm =
    Cmdliner.Arg.(non_empty & makeconv(string, []) & info([], ~doc, ~docv));

  let parse = command =>
    switch (command) {
    | [] => `Error((false, "command cannot be empty"))
    | [tool, ...args] =>
      let cmd = Cmd.(v(tool) |> addArgs(args));
      `Ok(cmd);
    };

  Cmdliner.Term.(ret(const(parse) $ commandTerm));
};

let cmdOptionTerm = (~doc, ~docv) => {
  let commandTerm =
    Cmdliner.Arg.(value & pos_all(string, []) & info([], ~doc, ~docv));

  let d = command =>
    switch (command) {
    | [] => `Ok(None)
    | [tool, ...args] =>
      let cmd = Cmd.(v(tool) |> addArgs(args));
      `Ok(Some(cmd));
    };

  Cmdliner.Term.(ret(const(d) $ commandTerm));
};

let setupLogTerm = {
  let pp_header = (ppf, (lvl: Logs.level, _header)) =>
    switch (lvl) {
    | Logs.App => Fmt.(styled(`Fg(`Magenta), any("info ")))(ppf, ())
    | Logs.Error => Fmt.(styled(`Fg(`Red), any("error ")))(ppf, ())
    | Logs.Warning => Fmt.(styled(`Fg(`Yellow), any("warn ")))(ppf, ())
    | Logs.Info => Fmt.(styled(`Fg(`Green), any("info ")))(ppf, ())
    | Logs.Debug => Fmt.(styled(`Fg(`Cyan), any("debug ")))(ppf, ())
    };

  let lwt_reporter = () => {
    let buf_fmt = (~like) => {
      let b = Buffer.create(512);
      (
        Fmt.with_buffer(~like, b),
        () => {
          let m = Buffer.contents(b);
          Buffer.reset(b);
          m;
        },
      );
    };

    let mutex = Lwt_mutex.create();
    let (app, app_flush) = buf_fmt(~like=Fmt.stderr);
    let (dst, dst_flush) = buf_fmt(~like=Fmt.stderr);
    let reporter = Logs_fmt.reporter(~pp_header, ~app, ~dst, ());
    let report = (src, level, ~over, k, msgf) => {
      let k = () => {
        let write = () => {
          let%lwt () =
            switch (level) {
            | Logs.App =>
              let msg = app_flush();
              let%lwt () = Lwt_io.write(Lwt_io.stderr, msg);
              let%lwt () = Lwt_io.flush(Lwt_io.stderr);
              Lwt.return();
            | _ =>
              let msg = dst_flush();
              let%lwt () = Lwt_io.write(Lwt_io.stderr, msg);
              let%lwt () = Lwt_io.flush(Lwt_io.stderr);
              Lwt.return();
            };

          Lwt.return();
        };

        let writeAndPreserveProgress = () =>
          Lwt_mutex.with_lock(mutex, () =>
            switch (ProgressReporter.status()) {
            | None =>
              let%lwt () = write();
              Lwt.return();
            | Some(status) =>
              let%lwt () = ProgressReporter.clearStatus();
              let%lwt () = write();
              let%lwt () = ProgressReporter.setStatus(status);
              Lwt.return();
            }
          );

        let unblock = () => {
          over();
          Lwt.return_unit;
        };
        Lwt.finalize(writeAndPreserveProgress, unblock) |> Lwt.ignore_result;
        k();
      };

      reporter.Logs.report(src, level, ~over=() => (), k, msgf);
    };

    {Logs.report: report};
  };

  let setupLog = (style_renderer, level) => {
    /**********************************************************************/
    /*   Because, Fmt_cli accept renderer as is without checking if       */
    /*   terminal is dumb. It's then our responsibility to check if the   */
    /*   terminal is dumb or not. This is why we default to None, so that */
    /*   we fallback to Fmt_cli's default behaviour which is what we want */
    /*   anyways                                                          */
    /*                                                                    */
    /* let style_renderer = match style_renderer with                     */
    /* | Some r -> r                                                      */
    /* | None ->                                                          */
    /*     let dumb =                                                     */
    /*       try match Sys.getenv "TERM" with                             */
    /*       | "dumb" | "" -> true                                        */
    /*       | _ -> false                                                 */
    /*       with                                                         */
    /*       Not_found -> true                                            */
    /*     in                                                             */
    /**********************************************************************/

    switch (style_renderer) {
    | None => Fmt_tty.setup_std_outputs()
    | Some(style_renderer) => Fmt_tty.setup_std_outputs(~style_renderer, ())
    };

    Logs.set_level(level);
    Logs.set_reporter(lwt_reporter());
  };

  Cmdliner.(
    Term.(
      const(setupLog)
      $ Fmt_cli.style_renderer(~docs=Cmdliner.Manpage.s_common_options, ())
      $ Logs_cli.level(
          ~docs=Cmdliner.Manpage.s_common_options,
          ~env=Cmd.Env.info("ESY__LOG"),
          (),
        )
    )
  );
};

/* let runAsyncToCmdlinerRet = res => */
/*   switch (Lwt_main.run(res)) { */
/*   | Ok(v) => `Ok(v) */
/*   | Error(error) => */
/*     Lwt_main.run(ProgressReporter.clearStatus()); */
/*     `Error((false, error)); */
/*   }; */
