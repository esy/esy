(**

  Utilities for measuring perf.

 *)

val measure : label:string -> (unit -> 'a) -> 'a
(** Measure and log execution time. *)

val measureLwt : label:string -> (unit -> 'a Lwt.t) -> 'a Lwt.t
(** Measure and log execution time of an Lwt promise. *)

