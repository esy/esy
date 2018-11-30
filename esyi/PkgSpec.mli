(** PkgSpec allows to specify a subset of packages of the sandbox. *)

type t =
  | All
  | Root
  | Package of string
  | Dependencies
  | Installed
  | Linked
