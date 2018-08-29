(**
 * This represents sandbox.
 *)

type t = {
  root : Package.t;
  scripts : Manifest.Scripts.t;
  env : Manifest.Env.t;
}

type info = (Path.t * float) list

(** Check if a directory is a sandbox *)
val isSandbox : Path.t -> bool RunAsync.t

(** Init sandbox from given the config *)
val ofDir : Config.t -> (t * info) RunAsync.t
