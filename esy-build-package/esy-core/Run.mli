type 'a t = ('a, error) result
and error

val return : 'a -> 'a t
val error : string -> 'a t

module Syntax : sig

  val return : 'a -> 'a t
  val error : string -> 'a t

  module Let_syntax : sig
    val bind : f:('a -> 'b t) -> 'a t -> 'b t
  end
end

val withContext : string -> 'a t -> 'a t

val formatError : error -> string

val liftOfSingleLineError : ('a, string) result -> 'a t

val foldLeft : f:('a -> 'b -> 'a t) -> init:'a -> 'b list -> 'a t
