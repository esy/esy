(** PkgSpec allows to specify a subset of packages of the sandbox. *)

type t =
  | Root
  | ByName of string
  | ByNameVersion of (string * Version.t)
  | ById of PackageId.t

val matches : PackageId.t -> t -> PackageId.t -> bool

val pp : t Fmt.t
val parse : string -> (t, string) result

val of_yojson : t Json.decoder
