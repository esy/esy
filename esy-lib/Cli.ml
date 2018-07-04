module ProgressReporter = struct

  type t = {
    mutable status : string;
    statusLock : Lwt_mutex.t;
  }

  let make () =
    {status = ""; statusLock = Lwt_mutex.create ()}

  let hide s =
    let len = String.length s in
    if len > 0
    then
      let s = Printf.sprintf "\r%*s\r" len "" in
      Lwt_io.write Lwt_io.stderr s
    else
      Lwt.return ()

  let show s =
    Lwt_io.write Lwt_io.stderr s

  let status r =
    r.status

  let clearStatus r =
    Lwt_mutex.with_lock r.statusLock begin fun () ->
      hide r.status;%lwt
      r.status <- "";
      Lwt.return ()
    end

  let setStatus status r =
    Lwt_mutex.with_lock r.statusLock begin fun () ->
      hide r.status;%lwt
      r.status <- status;
      show r.status
    end

  let finish r =
    Lwt_main.run (hide r.status)
end

module Progress = struct
  let reporter = ref None

  let init () =
    reporter := Some (ProgressReporter.make ())

  let finish () =
    match !reporter with
    | None -> ()
    | Some reporter -> ProgressReporter.finish reporter

  let setStatus status =
    match !reporter with
    | None -> Lwt.return ()
    | Some reporter -> ProgressReporter.setStatus status reporter

  let clearStatus () =
    match !reporter with
    | None -> Lwt.return ()
    | Some reporter -> ProgressReporter.clearStatus reporter

  let status () =
    match !reporter with
    | None -> ""
    | Some reporter -> reporter.status
end

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
      Fmt.(styled `Blue (unit "info ")) ppf ()
    | Logs.Error ->
      Fmt.(styled `Red (unit "error ")) ppf ()
    | Logs.Warning ->
      Fmt.(styled `Yellow (unit "warn ")) ppf ()
    | Logs.Info ->
      Fmt.(styled `Blue (unit "info ")) ppf ()
    | Logs.Debug ->
      Fmt.(unit "debug ") ppf ()
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
    let withPreserveStatus f =
      let status = Progress.status () in
      let%lwt () = Progress.clearStatus () in
      let%lwt () = f () in
      let%lwt () = Progress.setStatus status in
      Lwt.return ()
    in
    let report src level ~over k msgf =
      let k () =
        let write () =
          let%lwt () =
            withPreserveStatus begin fun () ->
              match level with
              | Logs.App -> Lwt_io.write Lwt_io.stderr (app_flush ())
              | _ -> Lwt_io.write Lwt_io.stderr (dst_flush ())
            end
          in
          Lwt.return ()
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
    Logs.set_reporter (lwt_reporter ());
    Progress.init ()
  in
  let open Cmdliner in
  Term.(
    const setupLog
    $ Fmt_cli.style_renderer ()
    $ Logs_cli.level ~env:(Arg.env_var "ESY__LOG") ())

let eval ?(argv=Sys.argv) ~defaultCommand ~commands () =
  let result = Cmdliner.Term.eval_choice ~argv defaultCommand commands in
  Lwt_main.run (Progress.clearStatus ());
  result
