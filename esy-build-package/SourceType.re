[@deriving (show, eq, ord)]
type t =
  | Immutable
  | Transient;
let of_yojson = (json: Yojson.Safe.json) =>
  switch (json) {
  | `String("immutable") => Ok(Immutable)
  | `String("transient") => Ok(Transient)
  | _ => Error("invalid buildType")
  };
let to_yojson = (sourceType: t) =>
  switch (sourceType) {
  | Immutable => `String("immutable")
  | Transient => `String("transient")
  };
