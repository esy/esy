(**
 * A computation which might result in an error.
 *)
type 'v t = ('v, error) result

and error

(**
 * Failied computation with an error specified by a message.
 *)
val return : 'v -> 'v t

(**
 * Failied computation with an error specified by a message.
 *)
val error : string -> 'v t

(**
 * Same with [error] but defined with a formatted string.
 *)
val errorf : ('a, Format.formatter, unit, 'v t) format4 -> 'a

(**
 * Wrap computation with a context which will be reported in case of error
 *)
val context : 'v t -> string -> 'v t

(**
 * Same as [context] but defined with a formatter.
 *)
val contextf : 'v t -> ('a, Format.formatter, unit, 'v t) format4 -> 'a

(**
 * Wrap computation with a context which will be reported in case of error
 *)
val withContextOfLog : ?header:string -> string -> 'a t -> 'a t

(**
 * Format error.
 *)
val formatError : error -> string

val ppError : error Fmt.t

(**
 * Run computation and raise an exception in case of failure.
 *)
val runExn : ?err : string -> 'a t -> 'a


val ofStringError : ('a, string) result -> 'a t

val ofBosError : ('a, [< `Msg of string | `CommandError of Bos.Cmd.t * Bos.OS.Cmd.status ]) result -> 'a t

val ofOption : ?err : string -> 'a option -> 'a t

val toResult : 'a t -> ('a, string) result

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
  val errorf : ('a, Format.formatter, unit, 'v t) format4 -> 'a

  module Let_syntax : sig
    val bind : f:('a -> 'b t) -> 'a t -> 'b t
    val map : f:('a -> 'b) -> 'a t -> 'b t
  end
end

module List : sig
  val foldLeft : f:('a -> 'b -> 'a t) -> init:'a -> 'b list -> 'a t

  val waitAll : unit t list -> unit t
  val mapAndWait : f:('a -> unit t) -> 'a list -> unit t
end

