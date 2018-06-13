(**
 * Package paths of the form
 *
 *   pkg1/pkg2
 *   @scope/pkg1/pkg2
 *   **/pkg2
 *
 *)

(** Pair of a path and a package name *)
type t = segment list * string

and segment =
  | Pkg of string
  | AnyPkg

val show : t -> string
val parse : string -> (t, string) result

val equal : t -> t -> bool
val compare : t -> t -> int

val to_yojson : t Json.encoder
val of_yojson : t Json.decoder
