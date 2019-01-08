(**
 * Commands.
 *
 * Command is a tool and a list of arguments.
 *)

type t

val to_yojson : t Json.encoder
val of_yojson : t Json.decoder

(** Produce a command supplying a tool. *)
val v : string -> t

val ofPath : Path.t -> t

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
val ofToolAndArgs : string * string list -> t

(**
 * Get a tuple of a tool and a list of argv suitable to be passed into
 * Lwt_process or Unix family of functions.
 *)
val getToolAndLine : t -> string * string array

val getTool : t -> string
val getArgs : t -> string list

val mapTool : (string -> string) -> t -> t

include S.PRINTABLE with type t := t
include S.COMPARABLE with type t := t

val resolveInvocation : string list -> t -> (t, [> `Msg of string ]) result
(** TODO: remove away, use resolveInvocation instead *)
val resolveCmd : string list -> string -> (string, [> `Msg of string ]) result

(**
 * Interop with Bos.Cmd.t
 *  TODO: get rid of that
 *)
val toBosCmd : t -> Bos.Cmd.t
val ofBosCmd : Bos.Cmd.t -> (t, [> `Msg of string ]) result

val ofListExn : string list -> t
