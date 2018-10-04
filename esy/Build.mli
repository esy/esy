(**
 * Build tasks.
 *)

(**
 * Build all tasks.
 *)
val buildAll :
  ?force:[`ForRoot | `No | `Yes | `Select of Set.Make(String).t]
  -> ?buildOnly:[`ForRoot | `No | `Yes]
  -> concurrency:int
  -> Sandbox.t
  -> Task.t
  -> unit RunAsync.t

(**
 * Build all dependencies.
 *)
val buildDependencies :
  ?force:[`ForRoot | `No | `Yes | `Select of Set.Make(String).t]
  -> ?buildOnly:[`ForRoot | `No | `Yes]
  -> concurrency:int
  -> Sandbox.t
  -> Task.t
  -> unit RunAsync.t

(**
 * Build a single task.
 *)
val buildTask :
  ?quiet:bool
  -> ?force:bool
  -> ?logPath:Sandbox.Path.t
  -> buildOnly:bool
  -> Sandbox.t
  -> Task.t
  -> unit RunAsync.t
