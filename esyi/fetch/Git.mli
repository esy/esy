(**
 * Git repository manipulation.
 *
 * The implementation uses git command.
 *)

(** Clone repositoryu from [remote] into [dst] local path. *)
val clone :
  dst:Fpath.t
  -> remote:string
  -> unit RunAsync.t

(** Checkout the [ref] in the [repo] *)
val checkout :
  ref:string
  -> repo:Fpath.t
  -> unit RunAsync.t
