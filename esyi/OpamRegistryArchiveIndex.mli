(**
 * opam registry archive URL index
 *)

type t

type record = private {
  url: string;
  md5: string
}

val init :
  cfg:Config.t
  -> unit
  -> t RunAsync.t
(** Configure opam registry archive URL index. *)

val find :
  name:OpamPackage.Name.t
  -> version:OpamPackage.Version.t
  -> t
  -> record option
(** Find record for a given opam package name, version. *)
