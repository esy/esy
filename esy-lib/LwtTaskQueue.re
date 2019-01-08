type t = Lwt_pool.t(unit);

let create = (~concurrency, ()) =>
  Lwt_pool.create(concurrency, () => Lwt.return());

let submit = (q, f) => Lwt_pool.use(q, f);

let queued = (q, f, ()) => Lwt_pool.use(q, f);
