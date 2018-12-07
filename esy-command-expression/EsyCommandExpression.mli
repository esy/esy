(**
 * Command expression language
 *
 * This is a small language which allows to define build commands which use
 * parameters from the build configuration.
 *
 * Constructs supported are
 *
 * - Variables:
 *    name
 *
 * - String literals:
 *    "value"
 *
 * - Colons:
 *    :
 *
 * - Path separators:
 *    /
 *
 * - Environment variables
 *    $NAME
 *
 * - Conditionals:
 *    cond ? then : else
 *
 * - Logical AND
 *    cond && cond2 ? then : else
 *
 * - Parens (for grouping)
 *    (A B)
 *
 * - Sequences (treated as concatenations):
 *    A B C
 *
 * Examples
 *
 * - #{"--" (@opam/lwt.installed ? "enable" : "disable") "-lwt"}
 *
 *)

module Value : sig
  type t =
    | String of string
    | Bool of bool
  val equal : t -> t -> bool
  val compare : t -> t -> int
  val show : t -> string
  val pp : Format.formatter -> t -> unit
end


val bool : bool -> Value.t
val string : string -> Value.t

type scope = string option * string -> Value.t option

(** Render command expression into a string given the [scope]. *)
val render :
  ?envVar:(string -> (Value.t, string) result)
  -> ?pathSep:string
  -> ?colon:string
  -> scope:scope
  -> string
  -> (string, string) result
