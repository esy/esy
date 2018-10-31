open EsyLib;

external replace: (Path.t, string, string) => result(unit, string) =
  "caml_fastreplacestring";
