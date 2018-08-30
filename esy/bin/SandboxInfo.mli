(**
 * Cache info about sandbox.
 *)

open Esy

type t = private {
  sandbox : Sandbox.t;
  task : Task.t;
  commandEnv : Environment.Bindings.t;
  sandboxEnv : Environment.Bindings.t;
  info : Sandbox.info;
}

val ofConfig : Config.t -> Path.t -> t RunAsync.t

val ocaml : sandbox:Sandbox.t -> t -> Path.t RunAsync.t
val ocamlfind : sandbox:Sandbox.t -> t -> Path.t RunAsync.t

val libraries :
  sandbox:Sandbox.t
  -> ocamlfind:Path.t
  -> ?builtIns:string list
  -> ?task:Task.t
  -> unit
  -> string list RunAsync.t

val modules :
  ocamlobjinfo:Path.t
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
    sandbox:Sandbox.t
    -> ocamlfind:Path.t
    -> task:Task.t
    -> string
    -> meta RunAsync.t
end
