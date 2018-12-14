(**
 * Git repository manipulation.
 *
 * The implementation uses git command.
 *)

type ref = string
type commit = string
type remote = string

(** Clone repository from [remote] into [dst] local path. *)
val clone :
  ?branch:string
  -> ?depth:int
  -> dst:Fpath.t
  -> remote:remote
  -> unit
  -> unit RunAsync.t

(** Pull into [repo] from [source] branch [branchSpec] *)
val pull :
  ?force:bool
  -> ?ffOnly:bool
  -> ?depth:int
  -> remote:remote
  -> repo:Fpath.t
  -> branchSpec:remote
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
  -> commit option RunAsync.t

val isCommitLike : string -> bool

module ShallowClone : sig
  val update : branch:remote -> dst:Fpath.t -> remote -> unit RunAsync.t
end
