(**
 * A computation which might result in an error.
 *)
type 'a t = ('a, error) result

and error

val return : 'a -> 'a t

val error : string -> 'a t

(**
 * Wrap computation with a context which will be reported in case of error
 *)
val withContext : string -> 'a t -> 'a t

(**
 * Wrap computation with a context which will be reported in case of error
 *)
val withContextOfLog : ?header:string -> string -> 'a t -> 'a t

(**
 * Format error.
 *)
val formatError : error -> string

(**
 * Run computation and raise an exception in case of failure.
 *)
val runExn : ?err : string -> 'a t -> 'a


val ofStringError : ('a, string) result -> 'a t

val ofBosError : ('a, [< `Msg of string]) result -> 'a t

val ofOption : ?err : string -> 'a option -> 'a t

(**
 * Convenience module which is designed to be openned locally with the
 * code which heavily relies on Run.t.
 *
 * This also brings Let_syntax module into scope and thus compatible with
 * ppx_let.
 *
 * Example
 *
 *    let open Run.Syntax in
 *    let%bind v = getNumber ... in
 *    if v > 10
 *    then return (v + 1)
 *    else error "Less than 10"
 *
 *)
module Syntax : sig

  val return : 'a -> 'a t
  val error : string -> 'a t

  module Let_syntax : sig
    val bind : f:('a -> 'b t) -> 'a t -> 'b t
  end
end

module List : sig
  val foldLeft : f:('a -> 'b -> 'a t) -> init:'a -> 'b list -> 'a t
end

