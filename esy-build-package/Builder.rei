
let build :
  (~buildOnly: bool=?, ~force: bool=?, Config.t, BuildTask.t) =>
  Run.t(unit, 'b)

let withBuildEnv :
  (~commit: bool=?, Config.t, BuildTask.t,
  (Bos.Cmd.t =>
   Run.t(unit, 'err),
  Bos.Cmd.t =>
  result(unit, [> `CommandError(Bos.Cmd.t, Bos.OS.Cmd.status) | `Msg(string) ]),
  unit) =>
  result(unit,
          ([> `CommandError(Bos.Cmd.t, Bos.OS.Cmd.status) | `Msg(string) ]
           as 'a))) =>
  result(unit, 'a)
