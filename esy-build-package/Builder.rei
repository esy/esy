let build:
  (~buildOnly: bool=?, ~force: bool=?, Config.t, Task.t) =>
  Run.t(unit, 'b);

let withBuildEnv:
  (
    ~commit: bool=?,
    Config.t,
    Task.t,
    (
      Bos.Cmd.t =>
      result(
        unit,
        [> | `CommandError(Bos.Cmd.t, Bos.OS.Cmd.status) | `Msg(string)] as 'a,
      ),
      Bos.Cmd.t => result(unit, 'a),
      unit
    ) =>
    result(
      unit,
      [> | `CommandError(Bos.Cmd.t, Bos.OS.Cmd.status) | `Msg(string)] as 'b,
    )
  ) =>
  result(unit, 'b);
