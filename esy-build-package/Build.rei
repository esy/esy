type t = pri {
  task: Task.t,
  sourcePath: EsyLib.Path.t,
  storePath: EsyLib.Path.t,
  installPath: EsyLib.Path.t,
  stagePath: EsyLib.Path.t,
  buildPath: EsyLib.Path.t,
  lockPath: EsyLib.Path.t,
  infoPath: EsyLib.Path.t,
  env: Bos.OS.Env.t,
  build: list(Bos.Cmd.t),
  install: list(Bos.Cmd.t),
};

/** Build task. */
let build:
  (~buildOnly: bool=?, ~force: bool=?, ~cfg: Config.t, Task.t) =>
  Run.t(unit, 'b);

/** Run computation with build. */
let withBuild:
  (
    ~commit: bool=?,
    ~cfg: Config.t,
    Task.t,
    (
      ~run: Bos.Cmd.t => Run.t(unit, 'a),
      ~runInteractive: Bos.Cmd.t => Run.t(unit, 'a),
      t
    ) => Run.t(unit, 'b),
  ) =>
  Run.t(unit, 'b);
