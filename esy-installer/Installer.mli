module type IO = sig

  type 'v computation
  val return : 'v -> 'v computation
  val error : string -> 'v computation
  val bind : f : ('v1 -> 'v2 computation) -> 'v1 computation -> 'v2 computation
  val handle : 'v computation -> ('v, string) result computation

  module Fs : sig
    val mkdir : Fpath.t -> unit computation
    val readdir : Fpath.t -> Fpath.t list computation
    val read : Fpath.t -> string computation
    val write : ?perm:int -> data:string -> Fpath.t -> unit computation
    val stat : Fpath.t -> Unix.stats computation
  end
end

(** An installer which is parametrized over IO *)
module type INSTALLER = sig
  type 'v computation

  (** Perform installation given the root and a prefix. *)
  val run : rootPath:Fpath.t -> prefixPath:Fpath.t -> string option -> unit computation
end

module Make (Io : IO) : INSTALLER with type 'v computation = 'v Io.computation
