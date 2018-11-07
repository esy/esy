(**

  Shell parameter expansion.

  This is a limited implementation of shell parameter expansion as found imn
  popular Unix shells like sh, bash and so on.

  The only supported constructs are:

    - substitution: `$VALUE` or `${VALUE}`
    - substitution with default: `${VALUE:-DEFAULT}`

 *)

type scope = string -> string option

val render :
  scope:scope
  -> string
  -> (string, string) result
(** Render string by expanding all shell parameters found. *)

val renderBatch :
  scope:scope
  -> string
  -> (string, string) result
(** Render string by expanding all batch parameters found. *)
