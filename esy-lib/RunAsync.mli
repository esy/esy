(**
 * An async computation which might result in an error.
 *)
type 'a t = 'a Run.t Lwt.t

val return : 'a -> 'a t

val error : string -> 'a t

(**
 * Wrap computation with a context which will be reported in case of error.
 *
 * Example usage:
 *
 *   let build = withContext "building ocaml" build in ...
 *
 * In case build fails the error message would look like:
 *
 *   Error: command not found aclocal
 *     While building ocaml
 *
 *)
val withContext : string -> 'a t -> 'a t
val withContextOfLog : ?header:string -> string -> 'a t -> 'a t

val waitAll : unit t list -> unit t
val joinAll : 'a t list -> 'a list t

val runExn : ?err : string -> 'a t -> 'a

module Syntax : sig

  val return : 'a -> 'a t

  val error : string -> 'a t

  module Let_syntax : sig
    val bind : f:('a -> 'b t) -> 'a t -> 'b t
  end
end

val liftOfRun : 'a Run.t -> 'a t
