/**
 * Run command.
*/;

type env =
  | CurrentEnv
  | CurrentEnvOverride(Astring.String.Map.t(string))
  | CustomEnv(Astring.String.Map.t(string));

let pp_env: Fmt.t(env);

let prepareEnv: env => option((StringMap.t(string), array(string)));

/** Run command. */

let run:
  (
    ~env: env=?,
    ~resolveProgramInEnv: bool=?,
    ~stdin: Lwt_process.redirection=?,
    ~stdout: Lwt_process.redirection=?,
    ~stderr: Lwt_process.redirection=?,
    Cmd.t
  ) =>
  RunAsync.t(unit);

/** Run command and collect stdout */

let runOut:
  (
    ~env: env=?,
    ~resolveProgramInEnv: bool=?,
    ~stdin: Lwt_process.redirection=?,
    ~stderr: Lwt_process.redirection=?,
    Cmd.t
  ) =>
  RunAsync.t(string);

/** Run command and return process exit status */

let runToStatus:
  (
    ~env: env=?,
    ~resolveProgramInEnv: bool=?,
    ~cwd: string=?,
    ~stdin: Lwt_process.redirection=?,
    ~stdout: Lwt_process.redirection=?,
    ~stderr: Lwt_process.redirection=?,
    Cmd.t
  ) =>
  RunAsync.t(Unix.process_status);

let withProcess:
  (
    ~env: env=?,
    ~resolveProgramInEnv: bool=?,
    ~cwd: string=?,
    ~stdin: Lwt_process.redirection=?,
    ~stdout: Lwt_process.redirection=?,
    ~stderr: Lwt_process.redirection=?,
    Cmd.t,
    Lwt_process.process_none => RunAsync.t('a)
  ) =>
  RunAsync.t('a);
