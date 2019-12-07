[@deriving (show, ord)]
type t =
  | InSource
  | JbuilderLike
  | OutOfSource
  | Unsafe;

let of_yojson = (json: Yojson.Safe.t) =>
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

module AsInPackageJson = {
  let of_yojson =
    fun
    | `String("_build") => Ok(JbuilderLike)
    | `String("unsafe") => Ok(Unsafe)
    | `Bool(true) => Ok(InSource)
    | `Bool(false) => Ok(OutOfSource)
    | _ => Error("expected false, true or \"_build\"");

  let to_yojson = (buildType: t) =>
    switch (buildType) {
    | InSource => `Bool(true)
    | JbuilderLike => `String("_build")
    | OutOfSource => `Bool(false)
    | Unsafe => `String("unsafe")
    };
};
