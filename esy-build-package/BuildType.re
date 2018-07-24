[@deriving (show, eq, ord)]
type t =
  | InSource
  | JbuilderLike
  | OutOfSource
  | Unsafe;
let of_yojson = (json: Yojson.Safe.json) =>
  switch (json) {
  | `String("in-source") => Ok(InSource)
  | `String("out-of-source") => Ok(OutOfSource)
  | `String("_build") => Ok(JbuilderLike)
  | `String("unsafe") => Ok(Unsafe)
  | _ => Error("invalid buildType")
  };
let to_yojson = (buildType: t) =>
  switch (buildType) {
  | InSource => `String("in-source")
  | JbuilderLike => `String("_build")
  | OutOfSource => `String("out-of-source")
  | Unsafe => `String("unsafe")
  };
