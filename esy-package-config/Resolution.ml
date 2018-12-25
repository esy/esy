[@@@ocaml.warning "-32"]
type t = {
  name : string;
  resolution : resolution;
}
[@@deriving ord, show]

and resolution =
  | Version of Version.t
  | SourceOverride of {source : Source.t; override : Json.t}
[@@@ocaml.warning "+32"]

let resolution_to_yojson resolution =
  match resolution with
  | Version v -> `String (Version.show v)
  | SourceOverride {source; override} ->
    `Assoc [
      "source", Source.to_yojson source;
      "override", override;
    ]

let resolution_of_yojson json =
  let open Result.Syntax in
  match json with
  | `String v ->
    let%bind version = Version.parse v in
    return (Version version)
  | `Assoc _ ->
    let%bind source = Json.Decode.fieldWith ~name:"source" Source.relaxed_of_yojson json in
    let%bind override = Json.Decode.fieldWith ~name:"override" Json.of_yojson json in
    return (SourceOverride {source; override;})
  | _ -> Error "expected string or object"

let digest {name; resolution} =
  Digestv.(
    empty
    |> add (string name)
    |> add (json (resolution_to_yojson resolution))
  )

let show ({name; resolution;} as r) =
  let resolution =
    match resolution with
    | Version version -> Version.show version
    | SourceOverride { source; override = _; } ->
      Source.show source ^ "@" ^ (Digestv.toHex (digest r))
  in
  name ^ "@" ^ resolution

let pp fmt r = Fmt.string fmt (show r)
