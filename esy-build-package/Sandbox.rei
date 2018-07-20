/*

    Sandboxed execution of commands.

 */

type pattern =
  | Subpath(string)
  | Regex(string);

type config = {
  allowWrite: list(pattern)
};

type sandbox('err) =
  (~env: Task.Env.t, Bos.Cmd.t) =>
  Run.t(
    (~err: Bos.OS.Cmd.run_err, Bos.OS.Cmd.run_in) => Bos.OS.Cmd.run_out,
    'err,
  );

let init : config => Run.t(sandbox('err), _)

