type t

type location =
  | Link of {
      path : Path.t;
      manifest : ManifestSpec.Filename.t option;
    }
  | Install of {
      path : Path.t;
      source : Source.t;
    }

include S.JSONABLE with type t := t

val mem : PackageId.t -> t -> bool
val find : PackageId.t -> t -> location option
val findExn : PackageId.t -> t -> location
val entries : t -> (PackageId.t * location) list

val empty : t
val add : PackageId.t -> location -> t -> t

val ofPath : Path.t -> t option RunAsync.t
val toPath : Path.t -> t -> unit RunAsync.t
