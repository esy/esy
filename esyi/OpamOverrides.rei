type t;

let init: (~cfg: Config.t, unit) => RunAsync.t(t);

let find:
  (~name: OpamPackage.Name.t, ~version: OpamPackage.Version.t, t) =>
  RunAsync.t(option(Package.Override.t));
