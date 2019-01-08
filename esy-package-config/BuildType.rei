/**

  Build type.

 */
type t =
  | /** Build writes to its source root (we preventively copy source root) */
    InSource
  | /** Build writes to _build dir inside of its source root (jbuilder/dune/ocamlbuild) */
    JbuilderLike
  | /** Build only writes to a directory specified via $cur__target_dir */
    OutOfSource
  | /** Build write to its source root (but we don't prevent that) */
    Unsafe;

let pp: Fmt.t(t);
let show: t => string;

include S.COMPARABLE with type t := t;
include S.JSONABLE with type t := t;

/** JSON repr which is used in package.json */
module AsInPackageJson: {include S.JSONABLE with type t := t;};
