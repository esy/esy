
(** Scope which used to render command expressions *)
type scope = name -> value option
and name = string list
and value = string

(** Render command expression into a string given the [scope]. *)
val render :
  ?pathSep:string
  -> ?colon:string
  -> scope:scope
  -> string
  -> string Run.t
