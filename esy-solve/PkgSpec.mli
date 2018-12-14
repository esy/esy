(** PkgSpec allows to specify a subset of packages of the sandbox. *)

type t =
  | Root
  | ByName of string
  | ByNameVersion of (string * EsyInstall.Version.t)
  | ById of EsyInstall.PackageId.t

val pp : t Fmt.t
val parse : string -> (t, string) result
