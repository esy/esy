type t = {
  name: OpamPackage.Name.t;
  version: OpamPackage.Version.t;
  path : Path.t;
}

val digest : t -> Digest.t RunAsync.t

module Lock : sig
  type t

  include S.JSONABLE with type t := t
end

val toLock : sandbox:SandboxSpec.t -> t -> Lock.t RunAsync.t
val ofLock : sandbox:SandboxSpec.t -> Lock.t -> t RunAsync.t

include S.JSONABLE with type t := t

