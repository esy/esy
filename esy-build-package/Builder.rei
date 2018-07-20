let build:
  (~buildOnly: bool=?, ~force: bool=?, ~cfg: Config.t, Task.t) =>
  Run.t(unit, 'b);

let withBuildEnv:
  (
    ~commit: bool=?,
    ~cfg: Config.t,
    Task.t,
    (Bos.Cmd.t => Run.t(unit, 'a), Bos.Cmd.t => Run.t(unit, 'a), unit) => Run.t(unit, 'b)
  ) =>
  Run.t(unit, 'b);
