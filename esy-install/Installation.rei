open EsyPackageConfig;

type t;

type location = Path.t;

let pp_location: Fmt.t(location);
let show_location: location => string;

include S.JSONABLE with type t := t;

let mem: (PackageId.t, t) => bool;
let find: (PackageId.t, t) => option(location);
let findExn: (PackageId.t, t) => location;
let entries: t => list((PackageId.t, location));

let empty: t;
let add: (PackageId.t, location, t) => t;

let ofPath: Path.t => RunAsync.t(option(t));
let toPath: (Path.t, t) => RunAsync.t(unit);

let pp: Fmt.t(t);
