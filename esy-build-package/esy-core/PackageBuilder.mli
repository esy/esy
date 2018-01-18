(**
 * This module describes methods which are performed on build tasks through
 * "esy-build-package" package builder executable.
 *)

(**
 * Build task.
 *)
val build : BuildTask.t -> unit RunAsync.t

(*
 * Spawn an interactive shell inside tbuild environment of the task.
 *)
val buildShell : BuildTask.t -> unit RunAsync.t

(*
 * Execute a command inside build environment of the task.
 *)
val buildExec : BuildTask.t -> unit RunAsync.t
