(**
 * This module prrovides info about the current system we are running on.
 *
 * It does some I/O to query the system and if it fails then esy isn't operable
 * on the system at all.
 *)

(** Platform *)
module Platform : sig
  type t = Darwin | Linux | Cygwin | Windows | Unix | Unknown


  val host : t
  (** Platform we are currently running on *)

  include S.PRINTABLE with type t := t
  include S.COMPARABLE with type t := t
end

module Arch : sig
  type t = X86_32 | X86_64 | Ppc32 | Ppc64 | Arm32 | Arm64 | Unknown

  val host : t
  (** Arch we are currently running on *)

  include S.PRINTABLE with type t := t
  include S.COMPARABLE with type t := t

end

module Environment : sig
  (** Environment variable separator which is used for $PATH and etc *)
  val sep : ?platform:Platform.t -> ?name:string -> unit -> string

  (** Value of $PATH environment variable. *)
  val path : string list

  (** Helper method to normalize CRLF (Windows) text-context to LF (POSIX) *)
  val normalizeNewLines : string -> string
end
