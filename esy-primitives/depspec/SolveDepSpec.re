[@deriving ord]
type solvePackageId =
  | Self;

module Id = {
  [@deriving ord]
  type t = solvePackageId;

  let pp = fmt =>
    fun
    | Self => Esy_fmt.any("self", fmt, ());

  let self = Self;
};

include DepSpecF.Make(Id);

let self = Id.self;
