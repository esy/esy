type 'a t = {
  mutable queue : ('a scheduled * 'a computation) Queue.t;
  mutable running : int;
  concurrency : int;
}

and 'a computation = unit -> 'a Lwt.t
and 'a scheduled = 'a Lwt_condition.t

let create ~concurrency () = {
  queue = Queue.empty;
  running = 0;
  concurrency
}

let submit q f =
  let v = Lwt_condition.create () in

  let rec run (v, f) () =
    try%lwt
      let%lwt r = f () in
      q.running <- q.running - 1;
      Lwt.async next;
      Lwt.return (Lwt_condition.broadcast v r)
    with exn ->
      q.running <- q.running - 1;
      Lwt.async next;
      Lwt.return (Lwt_condition.broadcast_exn v exn)

  and next () =
    match Queue.dequeue q.queue with
    | Some task, queue ->
      q.queue <- queue;
      q.running <- q.running + 1;
      run task ()
    | None, _ -> Lwt.return ()
  in
  if q.running < q.concurrency then (
    q.running <- q.running + 1;
    Lwt.async (run (v, f))
  ) else
    q.queue <- Queue.enqueue (v, f) q.queue;
  Lwt_condition.wait v
