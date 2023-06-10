type t;
let dump: (t, string) => RunAsync.t(unit);
let conv: Esy_cmdliner.Arg.conv(t);
