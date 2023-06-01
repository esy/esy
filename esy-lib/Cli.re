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
    {status: None, statusLock: Lwt_mutex.create(), enabled};
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
    Esy_logs_lwt.app(m => m("%s: done", name));
  };

  (progress, finish);
};

let pathConv = {
  open Esy_cmdliner;
  let parse = Path.ofString;
  let print = Path.pp;
  Arg.conv(~docv="PATH", (parse, print));
};

let cmdConv = {
  open Esy_cmdliner;
  let parse = v => Ok(Cmd.v(v));
  let print = Cmd.pp;
  Arg.conv(~docv="COMMAND", (parse, print));
};

let checkoutConv = {
  open Esy_cmdliner;
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

let cmdTerm = (~doc, ~docv, makeconv) => {
  open Esy_cmdliner;
  let commandTerm =
    Arg.(non_empty & makeconv(string, []) & info([], ~doc, ~docv));

  let parse = command =>
    switch (command) {
    | [] => `Error((false, "command cannot be empty"))
    | [tool, ...args] =>
      let cmd = Cmd.(v(tool) |> addArgs(args));
      `Ok(cmd);
    };

  Term.(ret(const(parse) $ commandTerm));
};

let cmdOptionTerm = (~doc, ~docv) => {
  open Esy_cmdliner;
  let commandTerm =
    Arg.(value & pos_all(string, []) & info([], ~doc, ~docv));

  let d = command =>
    switch (command) {
    | [] => `Ok(None)
    | [tool, ...args] =>
      let cmd = Cmd.(v(tool) |> addArgs(args));
      `Ok(Some(cmd));
    };

  Term.(ret(const(d) $ commandTerm));
};

let setupLogTerm = {
  let pp_header = (ppf, (lvl: Esy_logs.level, _header)) =>
    switch (lvl) {
    | Esy_logs.App => Fmt.(styled(`Blue, any("info ")))(ppf, ())
    | Esy_logs.Error => Fmt.(styled(`Red, any("error ")))(ppf, ())
    | Esy_logs.Warning => Fmt.(styled(`Yellow, any("warn ")))(ppf, ())
    | Esy_logs.Info => Fmt.(styled(`Blue, any("info ")))(ppf, ())
    | Esy_logs.Debug => Fmt.(any("debug "))(ppf, ())
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
    let reporter = Esy_logs_fmt.reporter(~pp_header, ~app, ~dst, ());
    let report = (src, level, ~over, k, msgf) => {
      let k = () => {
        let write = () => {
          let%lwt () =
            switch (level) {
            | Esy_logs.App =>
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

      reporter.Esy_logs.report(src, level, ~over=() => (), k, msgf);
    };

    {Esy_logs.report: report};
  };

  let setupLog = (style_renderer, level) => {
    let style_renderer =
      switch (style_renderer) {
      | None => `None
      | Some(renderer) => renderer
      };

    Esy_fmt_tty.setup_std_outputs(~style_renderer, ());
    Esy_logs.set_level(level);
    Esy_logs.set_reporter(lwt_reporter());
  };

  Esy_cmdliner.(
    Term.(
      const(setupLog)
      $ Esy_fmt_cli.style_renderer(
          ~docs=Esy_cmdliner.Manpage.s_common_options,
          (),
        )
      $ Esy_logs_cli.level(
          ~docs=Esy_cmdliner.Manpage.s_common_options,
          ~env=Arg.env_var("ESY__LOG"),
          (),
        )
    )
  );
};

let runAsyncToEsy_cmdlinerRet = res =>
  switch (Lwt_main.run(res)) {
  | Ok(v) => `Ok(v)
  | Error(error) =>
    Lwt_main.run(ProgressReporter.clearStatus());
    Format.fprintf(Format.err_formatter, "@[%a@]@.", Run.ppError, error);
    `Error((false, "exiting due to errors above"));
  };
