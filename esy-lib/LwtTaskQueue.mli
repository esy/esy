type t

(**
 * Create a task queue.
 *
 * No more than `concurrency` number of tasks will be running at any time.
 *)
val create : concurrency:int -> unit -> t

(**
 * Submit a task to the queue.
 *)
val submit : t -> (unit -> 'a Lwt.t) -> 'a Lwt.t
