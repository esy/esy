type solvePackageId =
  | Self;

module Id: DepSpecF.ID with type t = solvePackageId;
include DepSpecF.T with type id = Id.t;

let self: Id.t;
