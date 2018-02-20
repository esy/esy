(**
 * Cache info about sandbox.
 *)

open Esy

type t = {
  sandbox : Sandbox.t;
  task : Task.t;
  commandEnv : Environment.t;
  sandboxEnv : Environment.t;
}

val ofConfig : Config.t -> t RunAsync.t
