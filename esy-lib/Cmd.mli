(**
 * Commands.
 *
 * Commands are non-empty lists of command line arguments.
 *)

type t

(** Produce a command supplying a tool. *)
val v : string -> t

(** Add a new argument to the command. *)
val (%) : t -> string -> t

(** Convert path to a string suitable to use with (%). *)
val p : Path.t -> string

(**
 * Add a new argument to the command.
 *
 * Same as (%) but with a flipped argument order.
 * Added for convenience usage with (|>).
 *)
val addArg : string -> t -> t

(**
 * Add a list of arguments to the command.
 *
 * it is convenient to use with (|>).
 *)
val addArgs : string list -> t -> t

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
(** TODO: remove away, use resolveInvocation instead *)
val resolveCmd : string list -> string -> (string, [> `Msg of string ]) result

(**
 * Interop with Bos.Cmd.t
 *  TODO: get rid of that
 *)
val toBosCmd : t -> Bos.Cmd.t
val ofBosCmd : Bos.Cmd.t -> (t, [> `Msg of string ]) result
