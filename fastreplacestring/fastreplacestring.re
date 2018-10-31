open EsyLib;

external replace : (Path.t, string, string) => unit = "caml_fastreplacestring";
