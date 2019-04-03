type t;
let dump: (t, string) => RunAsync.t(unit);
let conv: Cmdliner.Arg.conv(t);
