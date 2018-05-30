(**
 * Git repository manipulation.
 *
 * The implementation uses git command.
 *)

type ref = string

type remote = string

(** Clone repositoryu from [remote] into [dst] local path. *)
val clone :
  dst:Fpath.t
  -> remote:remote
  -> unit
  -> unit RunAsync.t

(** Checkout the [ref] in the [repo] *)
val checkout :
  ref:ref
  -> repo:Fpath.t
  -> unit
  -> unit RunAsync.t


  (** Resolve [ref] of the [remote] *)
val lsRemote :
  ?ref:ref
  -> remote:remote
  -> unit
  -> string RunAsync.t
