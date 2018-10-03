type t

type location =
  | Link of {
      path : Path.t;
      manifest : ManifestSpec.Filename.t option;
    }
  | Install of {
      path : Path.t;
    }

include S.JSONABLE with type t := t

val mem : Solution.Id.t -> t -> bool
val find : Solution.Id.t -> t -> location option

val empty : t
val add : Solution.Id.t -> location -> t -> t
