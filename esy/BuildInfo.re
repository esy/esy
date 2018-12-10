/**
 * Information about the task.
 */
module ModTime = {
  type t = float;
  let v = v => v;
  let equal = (a, b) => !(a -. b > 0.00000001);

  let pp = (fmt, v) => Fmt.pf(fmt, "%.8f", v);

  let to_yojson = v => `String(Printf.sprintf("%.8f", v));

  let of_yojson = json =>
    switch (json) {
    | `String(v) =>
      switch (float_of_string_opt(v)) {
      | Some(v) => Ok(v)
      | None => Error("not a float")
      }
    | _json => Error("expected string")
    };
};

[@deriving yojson]
type t = {
  idInfo: BuildId.Repr.t,
  timeSpent: [@encoding `String] float,
  sourceModTime: option(ModTime.t),
};

let toFile = (path: Path.t, info: t) => {
  let json = to_yojson(info);
  let data = Format.asprintf("%a", Json.Print.ppRegular, json);
  Fs.writeFile(~data, path);
};

let ofFile = (path: EsyLib.Path.t) => {
  open RunAsync.Syntax;
  if%bind (Fs.exists(path)) {
    let%bind json = Fs.readJsonFile(path);
    switch (of_yojson(json)) {
    | Ok(v) => return(Some(v))
    | Error(_err) => return(None)
    };
  } else {
    return(None);
  };
};
