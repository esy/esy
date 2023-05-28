(*---------------------------------------------------------------------------
   Copyright (c) 2015 The esy_logs programmers. All rights reserved.
   Distributed under the ISC license, see terms at the end of the file.
   esy_logs v0.7.0
  ---------------------------------------------------------------------------*)

let ( >>= ) = Lwt.bind

let lwt_reporter () =
  let buf_fmt ~like =
    let b = Buffer.create 512 in
   Esy_fmt.with_buffer ~like b,
    fun () -> let m = Buffer.contents b in Buffer.reset b; m
  in
  let app, app_flush = buf_fmt ~like:Fmt.stdout in
  let dst, dst_flush = buf_fmt ~like:Fmt.stderr in
  let reporter = Esy_logs_fmt.reporter ~app ~dst () in
  let report src level ~over k msgf =
    let k () =
      let write () = match level with
      | Esy_logs.App -> Lwt_io.write Lwt_io.stdout (app_flush ())
      | _ -> Lwt_io.write Lwt_io.stderr (dst_flush ())
      in
      let unblock () = over (); Lwt.return_unit in
      Lwt.finalize write unblock |> Lwt.ignore_result;
      k ()
    in
    reporter.Esy_logs.report src level ~over:(fun () -> ()) k msgf;
  in
  { Esy_logs.report = report }

let main () =
 Esy_fmt_tty.setup_std_outputs ();
  Esy_logs.set_level @@ Some Esy_logs.Debug;
  Esy_logs.set_reporter @@ lwt_reporter ();
  Lwt_main.run @@ begin
    Esy_logs_lwt.info (fun m -> m ~header:"START" ?tags:None "Starting main")
    >>= fun () -> Esy_logs_lwt.warn (fun m -> m "Hey be warned by %d." 7)
    >>= fun () -> Esy_logs_lwt.err (fun m -> m "Hey be errored.")
    >>= fun () -> Esy_logs_lwt.debug (fun m -> m "Be debugged a bit ?")
    >>= fun () -> Esy_logs_lwt.app (fun m -> m "Application console or stdout.")
    >>= fun () -> Esy_logs_lwt.info (fun m -> m "Ending main")
    >>= fun () -> exit (if (Esy_logs.err_count () > 0) then 1 else 0)
  end

let () = main ()

(*---------------------------------------------------------------------------
   Copyright (c) 2015 The esy_logs programmers

   Permission to use, copy, modify, and/or distribute this software for any
   purpose with or without fee is hereby granted, provided that the above
   copyright notice and this permission notice appear in all copies.

   THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
   WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
   MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
   ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
   WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
   ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
   OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
  ---------------------------------------------------------------------------*)
