/** Discovers opam files */
let discover:
  (Path.t, string) => RunAsync.t(list((ManifestSpec.kind, EsyLib.Path.t)));
