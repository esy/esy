[@deriving (show, ord)]
type t =
  | Immutable
  | ImmutableWithTransientDependencies
  | Transient;

let of_yojson = (json: Json.t) =>
  switch (json) {
  | `String("immutable") => Ok(Immutable)
  | `String("immutable-with-transient-dependencies") =>
    Ok(ImmutableWithTransientDependencies)
  | `String("transient") => Ok(Transient)
  | _ => Error("invalid buildType")
  };

let to_yojson = (sourceType: t) =>
  switch (sourceType) {
  | Immutable => `String("immutable")
  | ImmutableWithTransientDependencies =>
    `String("immutable-with-transient-dependencies")
  | Transient => `String("transient")
  };
