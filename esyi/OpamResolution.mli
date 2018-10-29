type t = {
  name: OpamPackage.Name.t;
  version: OpamPackage.Version.t;
  path : Path.t;
}

val lock : sandbox:SandboxSpec.t -> t -> t RunAsync.t

include S.JSONABLE with type t := t

