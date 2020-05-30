let rewritePrefix:
  (~origPrefix: Fpath.t, ~destPrefix: Fpath.t, Fpath.t) => Lwt.t(Run.t(unit));

let genSearchPrefixesForWin: (Fpath.t, Fpath.t) => list((string, string));
