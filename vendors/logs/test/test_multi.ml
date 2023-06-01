(* This code is in the public domain. *)

(* Example for installing multiple reporters. *)

let combine r1 r2 =
  let report = fun src level ~over k msgf ->
    let v = r1.Esy_logs.report src level ~over:(fun () -> ()) k msgf in
    r2.Esy_logs.report src level ~over (fun () -> v) msgf
  in
  { Esy_logs.report }

let () =
  let r1 = Esy_logs.format_reporter () in
  let r2 = Esy_logs_fmt.reporter () in
 Esy_fmt_tty.setup_std_outputs ();
  Esy_logs.set_reporter (combine r1 r2);
  Esy_logs.err (fun m -> m "HEY HO!");
  ()
