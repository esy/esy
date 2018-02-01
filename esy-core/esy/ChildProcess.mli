(**
 * Run command.
*)

type env = [
  | `CurrentEnv
  | `CurrentEnvOverride of Environment.Value.t
  | `CustomEnv of Environment.Value.t
]

val run :
  ?env:env
  -> ?resolveProgramInEnv:bool
  -> ?stdin:Lwt_process.redirection
  -> ?stdout:Lwt_process.redirection
  -> ?stderr:Lwt_process.redirection
  -> Cmd.t
  -> unit RunAsync.t

val runOut :
  ?env:env
  -> ?resolveProgramInEnv:bool
  -> ?stdin:Lwt_process.redirection
  -> ?stderr:Lwt_process.redirection
  -> Cmd.t
  -> string RunAsync.t

val withProcess :
  ?env:env
  -> ?resolveProgramInEnv:bool
  -> ?stdin:Lwt_process.redirection
  -> ?stdout:Lwt_process.redirection
  -> ?stderr:Lwt_process.redirection
  -> Cmd.t
  -> (Lwt_process.process_none -> 'a RunAsync.t)
  -> 'a RunAsync.t
