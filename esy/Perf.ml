let measureTime ~label f =
  let open RunAsync.Syntax in
  let before = Unix.gettimeofday () in
  let%bind res = f () in
  let after = Unix.gettimeofday () in
  let%lwt () =
    let spent = 1000.0 *. (after -. before) in
    Logs_lwt.debug (fun m -> m ~header:"time" "%s: %fms" label spent)
  in
  return res
