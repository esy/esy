type t =
  | Link of Dist.local
  | Install of {
      source : Dist.t * Dist.t list;
      opam : opam option;
    }

and opam = {
  name : OpamPackage.Name.t;
  version : OpamPackage.Version.t;
  path : Path.t;
}

val opam_to_yojson : opam Json.encoder
val opam_of_yojson : opam Json.decoder

val opamfiles : opam -> File.t list RunAsync.t

include S.JSONABLE with type t := t
