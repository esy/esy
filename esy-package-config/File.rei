type t;

let pp: Fmt.t(t);
let digest: t => RunAsync.t(Digestv.t);

let ofDir: Path.t => RunAsync.t(list(t));
let placeAt: (Path.t, t) => RunAsync.t(unit);
