type t = unit Lwt_pool.t

let create ~concurrency () =
  Lwt_pool.create concurrency (fun () -> Lwt.return ())

let submit q f =
  Lwt_pool.use q f

let queued q f =
  fun () -> Lwt_pool.use q f
