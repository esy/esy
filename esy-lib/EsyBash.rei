let getMingwRuntimePath:
  unit =>
  result(
    Fpath.t,
    [> | `CommandError(Bos.Cmd.t, Bos.OS.Cmd.status) | `Msg(string)],
  );

let getBinPath:
  unit =>
  result(
    Fpath.t,
    [> | `CommandError(Bos.Cmd.t, Bos.OS.Cmd.status) | `Msg(string)],
  );

let toEsyBashCommand:
  (~env: option(string)=?, Bos.Cmd.t) =>
  result(
    Bos.Cmd.t,
    [> | `CommandError(Bos.Cmd.t, Bos.OS.Cmd.status) | `Msg(string)],
  );

let normalizePathForCygwin:
  string =>
  result(
    string,
    [> | `CommandError(Bos.Cmd.t, Bos.OS.Cmd.status) | `Msg(string)],
  );

let normalizePathForWindows:
  Fpath.t =>
  result(
    Fpath.t,
    [> | `CommandError(Bos.Cmd.t, Bos.OS.Cmd.status) | `Msg(string)],
  );

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
