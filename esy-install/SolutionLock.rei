let toPath:
  (~digest: Digestv.t, Sandbox.t, Solution.t, Fpath.t) => RunAsync.t(unit);

let ofPath:
  (~digest: Digestv.t=?, Sandbox.t, Fpath.t) =>
  RunAsync.t(option(Solution.t));

let unsafeUpdateChecksum: (~digest: Digestv.t, Fpath.t) => RunAsync.t(unit);
