type commands =
  | OpamCommands(list(OpamTypes.command))
  | EsyCommands(CommandList.t)
  | NoCommands;

let commands_to_yojson: Json.encoder(commands);

type t = {
  name: option(string),
  version: option(Version.t),
  buildType: BuildType.t,
  build: commands,
  buildDev: option(CommandList.t),
  install: commands,
  patches: list((Path.t, option(OpamTypes.filter))),
  substs: list(Path.t),
  exportedEnv: ExportedEnv.t,
  buildEnv: BuildEnv.t,
};

let empty: (~name: option(string), ~version: option(Version.t), unit) => t;

include S.PRINTABLE with type t := t;

let to_yojson: Json.encoder(t);
