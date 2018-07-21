/*

    Sandboxed execution of commands.

 */

type pattern =
  | Subpath(string)
  | Regex(string);

type config = {
  allowWrite: list(pattern)
};

type sandbox('e)
  constraint 'e = Run.err('e);

/* Init sandbox */
let init : config => Run.t(sandbox(_), _);

/* Exec command in the sandbox. */
let exec : (~env : Bos.OS.Env.t, sandbox('err), Cmd.t) => 
  Run.t((~err: Bos.OS.Cmd.run_err, Bos.OS.Cmd.run_in) => Bos.OS.Cmd.run_out, 'err);

