let getMingwRuntimePath:
  unit =>
  result(
    Path.t,
    [> | `CommandError(Bos.Cmd.t, Bos.OS.Cmd.status) | `Msg(string)],
  );

let getBinPath:
  unit =>
  result(
    Path.t,
    [> | `CommandError(Bos.Cmd.t, Bos.OS.Cmd.status) | `Msg(string)],
  );

let toEsyBashCommand:
  (~env: option(string)=?, Bos.Cmd.t) =>
  result(
    Bos.Cmd.t,
    [> | `CommandError(Bos.Cmd.t, Bos.OS.Cmd.status) | `Msg(string)],
  );

let normalizePathForCygwin: string => string;
let normalizePathForWindows: Path.t => Path.t;

let run:
  Bos.Cmd.t =>
  result(
    unit,
    [> | `CommandError(Bos.Cmd.t, Bos.OS.Cmd.status) | `Msg(string)],
  );

let runOut:
  Bos.Cmd.t =>
  result(
    string,
    [> | `CommandError(Bos.Cmd.t, Bos.OS.Cmd.status) | `Msg(string)],
  );
