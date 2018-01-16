type 'a t = 'a Run.t Lwt.t

val return : 'a -> 'a t
val error : string -> 'a t

module Syntax : sig

  val return : 'a -> 'a t
  val error : string -> 'a t

  module Let_syntax : sig
    val bind : f:('a -> 'b t) -> 'a t -> 'b t
  end
end

