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

include module type of CommandExprTypes

(** Render command expression into a string given the [scope]. *)
val render :
  ?pathSep:string
  -> ?colon:string
  -> scope:scope
  -> string
  -> string Run.t

val parseExn :
  string
  -> Expr.t

val parse :
  string
  -> Expr.t Run.t
