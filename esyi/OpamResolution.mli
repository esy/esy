(** This represents a ref to a package from opam repository. *)

type t

val make :
  OpamPackage.Name.t 
  -> OpamPackage.Version.t 
  -> Path.t
  -> t

val name : t -> string
val version : t -> Version.t
val path : t -> Path.t

val files : t -> File.t list RunAsync.t
val opam : t -> OpamFile.OPAM.t RunAsync.t
val digest : t -> Digest.t RunAsync.t

module Lock : sig
  type t

  include S.JSONABLE with type t := t
end

val toLock : sandbox:SandboxSpec.t -> t -> Lock.t RunAsync.t
val ofLock : sandbox:SandboxSpec.t -> Lock.t -> t RunAsync.t

include S.JSONABLE with type t := t

