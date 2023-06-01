(* This code is in the public domain. *)

(* Example with tags and custom reporter. *)

let stamp_tag : Mtime.span Esy_logs.Tag.def =
  Esy_logs.Tag.def "stamp" ~doc:"Relative monotonic time stamp" Mtime.Span.pp

let stamp c = Esy_logs.Tag.(empty |> add stamp_tag (Mtime_clock.count c))

let run () =
  let rec wait n = if n = 0 then () else wait (n - 1) in
  let c = Mtime_clock.counter () in
  Esy_logs.info (fun m -> m "Starting run");
  let delay1, delay2, delay3 = 10_000, 20_000, 40_000 in
  Esy_logs.info (fun m -> m "Start action 1 (%d)." delay1 ~tags:(stamp c));
  wait delay1;
  Esy_logs.info (fun m -> m "Start action 2 (%d)." delay2 ~tags:(stamp c));
  wait delay2;
  Esy_logs.info (fun m -> m "Start action 3 (%d)." delay3 ~tags:(stamp c));
  wait delay3;
  Esy_logs.info (fun m -> m "Done." ?header:None ~tags:(stamp c));
  ()

let reporter ppf =
  let report src level ~over k msgf =
    let k _ = over (); k () in
    let with_stamp h tags k ppfesy_fmt =
      let stamp = match tags with
      | None -> None
      | Some tags -> Esy_logs.Tag.find stamp_tag tags
      in
      let dt = match stamp with None -> 0. | Some s -> Mtime.Span.to_us s in
      Format.kfprintf k ppf ("%a[%0+04.0fus] @[" ^^esy_fmt ^^ "@]@.")
        Esy_logs.pp_header (level, h) dt
    in
    msgf @@ fun ?header ?tagsesy_fmt -> with_stamp header tags k ppfesy_fmt
  in
  { Esy_logs.report = report }

let main () =
  Esy_logs.set_reporter (reporter (Format.std_formatter));
  Esy_logs.set_level (Some Esy_logs.Info);
  run ();
  run ();
  ()

let () = main ()
