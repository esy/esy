let pathConv =
  let open Cmdliner in
  let parse = Path.of_string in
  let print = Path.pp in
  Arg.conv ~docv:"PATH" (parse, print)

let cmdTerm ~doc ~docv =
  let open Cmdliner in
  let commandTerm =
    Arg.(non_empty & (pos_all string []) & (info [] ~doc ~docv))
  in
  let d command =
    match command with
    | [] ->
      `Error (false, "command cannot be empty")
    | tool::args ->
      let cmd = Cmd.(v tool |> addArgs args) in
      `Ok cmd
  in
  Term.(ret (const d $ commandTerm))

let cmdOptionTerm ~doc ~docv =
  let open Cmdliner in
  let commandTerm =
    Arg.(value & (pos_all string []) & (info [] ~doc ~docv))
  in
  let d command =
    match command with
    | [] ->
      `Ok None
    | tool::args ->
      let cmd = Cmd.(v tool |> addArgs args) in
      `Ok (Some cmd)
  in
  Term.(ret (const d $ commandTerm))

let setupLogTerm =
  let pp_header ppf ((lvl : Logs.level), _header) =
    match lvl with
    | Logs.App ->
      Fmt.(styled `Blue (unit "[INFO] ")) ppf ()
    | Logs.Error ->
      Fmt.(styled `Red (unit "[ERROR] ")) ppf ()
    | Logs.Warning ->
      Fmt.(styled `Yellow (unit "[WARNING] ")) ppf ()
    | Logs.Info ->
      Fmt.(styled `Blue (unit "[INFO] ")) ppf ()
    | Logs.Debug ->
      Fmt.(unit "[DEBUG] ") ppf ()
  in
  let lwt_reporter () =
    let buf_fmt ~like =
      let b = Buffer.create 512 in
      Fmt.with_buffer ~like b,
      fun () -> let m = Buffer.contents b in Buffer.reset b; m
    in
    let app, app_flush = buf_fmt ~like:Fmt.stdout in
    let dst, dst_flush = buf_fmt ~like:Fmt.stderr in
    let reporter = Logs_fmt.reporter ~pp_header ~app ~dst () in
    let report src level ~over k msgf =
      let k () =
        let write () = match level with
          | Logs.App -> Lwt_io.write Lwt_io.stdout (app_flush ())
          | _ -> Lwt_io.write Lwt_io.stderr (dst_flush ())
        in
        let unblock () = over (); Lwt.return_unit in
        Lwt.finalize write unblock |> Lwt.ignore_result;
        k ()
      in
      reporter.Logs.report src level ~over:(fun () -> ()) k msgf;
    in
    { Logs.report = report }
  in
  let setupLog style_renderer level =
    let style_renderer = match style_renderer with
      | None -> `None
      | Some renderer -> renderer
    in
    Fmt_tty.setup_std_outputs ~style_renderer ();
    Logs.set_level level;
    Logs.set_reporter (lwt_reporter ())
  in
  let open Cmdliner in
  Term.(
    const setupLog
    $ Fmt_cli.style_renderer ()
    $ Logs_cli.level ~env:(Arg.env_var "ESY__LOG") ())
