(**
 * This module prrovides info about the current system we are running on.
 *
 * It does some I/O to query the system and if it fails then esy isn't operable
 * on the system at all.
 *)

(** Platform *)
module Platform : sig
  type t = Darwin | Linux | Cygwin | Windows | Unix | Unknown

  val show : t -> string
  val pp : Format.formatter -> t -> unit

  (** Platform we are currently running on *)
  val host : t
end

(** Environment variable separator which is used for $PATH and etc *)
val envSep : string
