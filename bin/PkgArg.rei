open EsyFetch;

type t =
  | ByPkgSpec(PkgSpec.t)
  | ByPath(Path.t)
  | ByDirectoryPath(Path.t);

let root: t;

let pp: Fmt.t(t);
let parse: string => result(t, string);
let conv: Esy_cmdliner.Arg.conv(t);
