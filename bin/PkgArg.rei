open EsyInstall;

type t =
  | ByPkgSpec(PkgSpec.t)
  | ByPath(Path.t)
  | ByDirectoryPath(Path.t);

let root: t;

let pp: Fmt.t(t);
let parse: string => result(t, string);
let conv: Cmdliner.Arg.conv(t);
