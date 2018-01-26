(**
 * Run command.
 *)
val run :
  ?env:Environment.Value.t
  -> ?resolveProgramInEnv:bool
  -> ?stdin:Lwt_process.redirection
  -> ?stdout:Lwt_process.redirection
  -> ?stderr:Lwt_process.redirection
  -> Cmd.t
  -> unit RunAsync.t
