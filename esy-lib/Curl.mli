(**
 * Work with remote URLs via curl utility.
 *)

type response =
  | Success of string
  | NotFound

val getOrNotFound : string -> response RunAsync.t

val get : string -> string RunAsync.t
val download : output:Fpath.t -> string -> unit RunAsync.t
