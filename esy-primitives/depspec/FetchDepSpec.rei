type fetchPackageId =
  | Self
  | Root;

module Id: DepSpecF.ID with type t = fetchPackageId;
include DepSpecF.T with type id = Id.t;

let root: Id.t;
let self: Id.t;
