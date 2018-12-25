open EsyPackageConfig

type t

type location = Path.t

val pp_location : location Fmt.t
val show_location : location -> string

include S.JSONABLE with type t := t

val mem : PackageId.t -> t -> bool
val find : PackageId.t -> t -> location option
val findExn : PackageId.t -> t -> location
val entries : t -> (PackageId.t * location) list

val empty : t
val add : PackageId.t -> location -> t -> t

val ofPath : Path.t -> t option RunAsync.t
val toPath : Path.t -> t -> unit RunAsync.t
