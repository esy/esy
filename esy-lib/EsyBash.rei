let getMingwRuntimePath: unit => Path.t;
let getBinPath: unit => Path.t;

let toEsyBashCommand: (~env: option(string)=?, Bos.Cmd.t) => Bos.Cmd.t;

let normalizePathForCygwin: string => string;
let normalizePathForWindows: Path.t => Path.t;

let currentEnvWithMingwInPath: StringMap.t(string);

type error = [ | `CommandError(Bos.Cmd.t, Bos.OS.Cmd.status) | `Msg(string)];

let run: Bos.Cmd.t => result(unit, [> error]);

let runOut: Bos.Cmd.t => result(string, [> error]);
