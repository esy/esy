/*

    Sandboxed execution of commands.

 */

type pattern =
  | Subpath(string)
  | Regex(string);

type config = {allowWrite: list(pattern)};

type sandbox;

/* Init sandbox */
let init: (config, ~noSandbox: bool) => Run.t(sandbox, _);

/* Exec command in the sandbox. */
let exec:
  (~env: Bos.OS.Env.t, sandbox, Cmd.t) =>
  Run.t(
    (~err: Bos.OS.Cmd.run_err, Bos.OS.Cmd.run_in) => Bos.OS.Cmd.run_out,
    'err,
  );
