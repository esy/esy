(**
 * Commands.
 *
 * Commands are non-empty lists of command line arguments.
 *
 * We could have used Bos.Cmd.t (and we did before) but we want commands not to
 * be empty.
 *)

type t

val v : string -> t
val p : Path.t -> string

val add : t -> t -> t
val addArg : string -> t -> t
val addArgs : string list -> t -> t

val (%) : t -> string -> t
val (%%) : t -> t -> t

val getToolAndArgs : t -> string * string list
val getTool : t -> string
val getArgs : t -> string list

val pp : Format.formatter -> t -> unit
val show : t -> string
val toString : t -> string

val toList : t -> string list

val equal : t -> t -> bool
val compare : t -> t -> int

val resolveInvocation : string list -> t -> (t, [> `Msg of string ]) result
val resolveCmd : string list -> string -> (string, [> `Msg of string ]) result

val toBosCmd : t -> Bos.Cmd.t
val ofBosCmd : Bos.Cmd.t -> t
