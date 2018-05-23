include Fpath;

let addExt = add_ext;
let toString = to_string;

let of_yojson = (json: Yojson.Safe.json) =>
  switch (json) {
  | `String(v) =>
    switch (Fpath.of_string(v)) {
    | Ok(v) => Ok(v)
    | Error(`Msg(msg)) => Error(msg)
    }
  | _ => Error("invalid path")
  };

let to_yojson = (path: t) => `String(to_string(path));
