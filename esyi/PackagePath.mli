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

val parse : string -> (t, string) result

include S.PRINTABLE with type t := t
include S.COMPARABLE with type t := t
include S.JSONABLE with type t := t

val to_yojson : t Json.encoder
val of_yojson : t Json.decoder
