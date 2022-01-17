open Sexplib0.Sexp_conv;

[@deriving (ord, sexp_of)]
type t = (kind, string)
and kind =
  | Esy
  | Opam;

let show = ((_, fname)) => fname;

let pp = (fmt, (_, fname)) => Fmt.string(fmt, fname);

let ofString = fname =>
  Result.Syntax.(
    switch (fname) {
    | "" => errorf("empty filename")
    | "opam" => return((Opam, "opam"))
    | fname =>
      switch (Path.(getExt(v(fname)))) {
      | ".json" => return((Esy, fname))
      | ".opam" => return((Opam, fname))
      | _ => errorf("invalid manifest: %s", fname)
      }
    }
  );

let ofStringExn = fname =>
  switch (ofString(fname)) {
  | Ok(fname) => fname
  | Error(msg) => failwith(msg)
  };

let parser = {
  let make = fname =>
    switch (ofString(fname)) {
    | Ok(fname) => Parse.return(fname)
    | Error(msg) => Parse.fail(msg)
    };

  Parse.(take_while1(_ => true) >>= make);
};

let to_yojson = ((_, fname)) => `String(fname);

let of_yojson = json =>
  Result.Syntax.(
    switch (json) {
    | `String("opam") => return((Opam, "opam"))
    | `String(fname) => ofString(fname)
    | _ => error("invalid manifest filename")
    }
  );

let inferPackageName =
  fun
  | (Opam, "opam") => None
  | (Opam, fname) =>
    Some(
      "@opam/" ++ Path.(v(fname) |> Fpath.filename |> v |> remExt |> show),
    )
  | (Esy, fname) => Some(Path.(v(fname) |> remExt |> show));
