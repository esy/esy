(**
 * An async computation which might result in an error.
 *)

type 'a t = 'a Run.t Lwt.t

(**
 * Computation which results in a value.
 *)
val return : 'a -> 'a t

(**
 * Computation which results in an error.
 *)
val error : string -> 'a t

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
 * Same as with the [withContext] but will be formatted as differently, as a
 * single block of text.
 *)
val withContextOfLog : ?header:string -> string -> 'a t -> 'a t

val cleanup : 'a t -> (unit -> unit Lwt.t) -> 'a t
(**
 * [cleanup comp handler] executes [handler] in case of any error happens during
 * [comp] execution. Note that [handler] sometimes can fire two times.
 *)

(**
 * Run computation and throw an exception in case of a failure.
 *
 * Optional [err] will be used as error message.
 *)
val runExn : ?err : string -> 'a t -> 'a

(**
 * Convert [Run.t] into [t].
 *)
val ofRun : 'a Run.t -> 'a t

(**
 * Convert an Rresult into [t]
 *)
val ofStringError: ('a, string) result -> 'a t

val ofBosError : ('a, [< `Msg of string | `CommandError of Bos.Cmd.t * Bos.OS.Cmd.status ]) result -> 'a t

(**
 * Convert [option] into [t].
 *
 * [Some] will represent success and [None] a failure.
 *
 * An optional [err] will be used as an error message in case of failure.
 *)
val ofOption : ?err : string -> 'a option -> 'a t

(**
 * Convenience module which is designed to be openned locally with the
 * code which heavily relies on RunAsync.t.
 *
 * This also brings Let_syntax module into scope and thus compatible with
 * ppx_let.
 *
 * Example
 *
 *    let open RunAsync.Syntax in
 *    let%bind v = fetchNumber ... in
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
    val both : 'a t -> 'b t -> ('a * 'b) t
  end
end

(**
 * Work with lists of computations.
 *)
module List : sig

  val foldLeft :
    f:('a -> 'b -> 'a t)
    -> init:'a
    -> 'b list
    -> 'a t

  val filter :
    ?concurrency:int
    -> f:('a -> bool t)
    -> 'a list
    -> 'a list t

  val map :
    ?concurrency:int
    -> f:('a -> 'b t)
    -> 'a list
    -> 'b list t

  val mapAndJoin :
    ?concurrency:int
    -> f:('a -> 'b t)
    -> 'a list
    -> 'b list t

  val mapAndWait :
    ?concurrency:int
    -> f:('a -> unit t)
    -> 'a list
    -> unit t

  val waitAll : unit t list -> unit t
  val joinAll : 'a t list -> 'a list t
  val processSeq :
    f:('a -> unit t) -> 'a list -> unit t
end
