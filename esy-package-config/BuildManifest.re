module BuildType = {
  include BuildType;
  include BuildType.AsInPackageJson;
};

/* aliases for opam types with to_yojson implementations */
module OpamTypes = {
  type filter = OpamTypes.filter;

  let filter_to_yojson = filter => `String(OpamFilter.to_string(filter));

  [@deriving to_yojson]
  type command = (list(arg), option(filter))
  and arg = (simple_arg, option(filter))
  and simple_arg = OpamTypes.simple_arg = | CString(string) | CIdent(string);
};

[@deriving to_yojson]
type commands =
  | OpamCommands(list(OpamTypes.command))
  | EsyCommands(CommandList.t)
  | NoCommands;

let pp_commands = (fmt, cmds) =>
  switch (cmds) {
  | OpamCommands(cmds) =>
    let json = `List(List.map(~f=OpamTypes.command_to_yojson, cmds));
    Fmt.pf(fmt, "OpamCommands %a", Json.pp(~std=true), json);
  | EsyCommands(cmds) =>
    let json = CommandList.to_yojson(cmds);
    Fmt.pf(fmt, "EsyCommands %a", Json.pp(~std=true), json);
  | NoCommands => Fmt.pf(fmt, "NoCommands")
  };

type patch = (Path.t, option(OpamTypes.filter));

let patch_to_yojson = ((path, filter)) => {
  let filter =
    switch (filter) {
    | None => `Null
    | Some(filter) => `String(OpamFilter.to_string(filter))
    };

  `Assoc([("path", Path.to_yojson(path)), ("filter", filter)]);
};

let pp_patch = (fmt, (path, _)) => Fmt.pf(fmt, "Patch %a", Path.pp, path);

[@deriving (to_yojson, show)]
type t = {
  name: option(string),
  version: option(Version.t),
  buildType: BuildType.t,
  build: commands,
  buildDev: option(CommandList.t),
  install: commands,
  patches: list(patch),
  substs: list(Path.t),
  exportedEnv: ExportedEnv.t,
  buildEnv: BuildEnv.t,
};

let empty = (~name, ~version, ()) => {
  name,
  version,
  buildType: BuildType.OutOfSource,
  build: EsyCommands([]),
  buildDev: None,
  install: NoCommands,
  patches: [],
  substs: [],
  exportedEnv: ExportedEnv.empty,
  buildEnv: StringMap.empty,
};
