type t = {
  name: OpamPackage.Name.t;
  version: OpamPackage.Version.t;
  path : Path.t;
}

include S.JSONABLE with type t := t

