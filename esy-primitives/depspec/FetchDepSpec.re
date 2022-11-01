[@deriving ord]
type fetchPackageId =
  | Self
  | Root;

module Id = {
  [@deriving ord]
  type t = fetchPackageId;

  let pp = fmt =>
    fun
    | Self => Fmt.any("self", fmt, ())
    | Root => Fmt.any("root", fmt, ());

  let self = Self;
  let root = Root;
};

include DepSpecF.Make(Id);

let root = Id.root;
let self = Id.self;
