let loop s =
  for _ = 0 to 10 do
    Esy_logs.info (fun f -> f "%s.%s" s s)
  done

let () =
  Esy_logs_threaded.enable ();
  Esy_logs.set_level (Some Esy_logs.Debug);
  Esy_logs.set_reporter (Esy_logs_fmt.reporter ());
  let t1 = Thread.create loop "aaaa" in
  let t2 = Thread.create loop "bbbb" in
  loop "cccc";
  Thread.join t1;
  Thread.join t2
