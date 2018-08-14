(**

  Utilities for measuring perf.

 *)

val measure : label:string -> (unit -> 'a Lwt.t) -> 'a Lwt.t
(** Measure and log execution time. *)
