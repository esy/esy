type t =
  | Link of Source.link
  | Install of {
      source : Dist.t * Dist.t list;
      opam : OpamResolution.t option;
    }

include S.JSONABLE with type t := t
