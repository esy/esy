(**

  Environment.

 *)

(** Environment binding *)
module Binding : sig
  type 'v t
  val origin : 'v t -> string option
end

(** Environment representation over value type. *)
module type S = sig
  type ctx
  type value

  type t = value StringMap.t
  type env = t

  val empty : t
  val find : string -> t -> value option
  val add : string -> value -> t -> t
  val map : f:(string -> string) -> t -> t

  val render : ctx -> t -> string StringMap.t

  include S.COMPARABLE with type t := t
  include S.JSONABLE with type t := t

  (** Environment as a list of bindings. *)
  module Bindings : sig

    type t =
      value Binding.t list

    val pp : t Fmt.t

    val value : ?origin:string -> string -> value -> value Binding.t
    val prefixValue : ?origin:string -> string -> value -> value Binding.t
    val suffixValue : ?origin:string -> string -> value -> value Binding.t

    val empty : t
    val render : ctx -> t -> string Binding.t list
    val eval : ?platform : System.Platform.t -> ?init : env -> t -> (env, string) result
    val map : f:(string -> string) -> t -> t

    val current : t

    include S.COMPARABLE with type t := t
  end
end

module Make : functor (V : Abstract.STRING) ->
  S
    with type value = V.t
    and type ctx = V.ctx

(** Environment which holds strings as values. *)
include S with type value = string and type ctx = unit

val renderToShellSource :
  ?header:string
  -> ?platform : System.Platform.t
  -> Bindings.t
  -> string Run.t
(** Render environment bindings as shell export statements. *)

val renderToList :
  ?platform : System.Platform.t
  -> Bindings.t
  -> (string * string) list

val escapeDoubleQuote : string -> string
val escapeSingleQuote : string -> string
