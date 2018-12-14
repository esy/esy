type t = {
  id: PackageId.t;
  name: string;
  version: Version.t;
  source: PackageSource.t;
  overrides: Overrides.t;
  dependencies : PackageId.Set.t;
  devDependencies : PackageId.Set.t;
}

include S.COMPARABLE with type t := t
include S.PRINTABLE with type t := t

module Map : Map.S with type key := t
module Set : Set.S with type elt := t
