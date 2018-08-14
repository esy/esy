(**
 * Cache info about sandbox.
 *)

open Esy

type t = private {
  sandbox : Sandbox.t;
  task : Task.t;
  commandEnv : Environment.t;
  sandboxEnv : Environment.t;
}

val ofConfig : Config.t -> t RunAsync.t

val ocaml : cfg:Config.t -> t -> Path.t RunAsync.t
val ocamlfind : cfg:Config.t -> t -> Path.t RunAsync.t

val libraries :
  cfg:Config.t
  -> ocamlfind:Fpath.t
  -> ?builtIns:string list
  -> ?task:Task.t
  -> unit
  -> string list RunAsync.t

val modules :
  ocamlobjinfo:Fpath.t
  -> string
  -> string list RunAsync.t

module Findlib : sig
  type meta = {
    package : string;
    description : string;
    version : string;
    archive : string;
    location : string;
  }

  val query :
    cfg:Config.t
    -> ocamlfind:Fpath.t
    -> task:Task.t
    -> string
    -> meta RunAsync.t
end
