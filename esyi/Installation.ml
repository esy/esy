type location =
  | Link of {
      path : Path.t;
      manifest : ManifestSpec.Filename.t option;
    }
  | Install of {
      path : Path.t;
      source : Source.t;
    }

let location_to_yojson location =
  match location with
  | Link {path; manifest;} ->
    `Assoc [
      "type", `String "link";
      "path", Path.to_yojson path;
      "manifest", Json.Encode.opt ManifestSpec.Filename.to_yojson manifest;
    ]
  | Install {path; source;} ->
    `Assoc [
      "type", `String "install";
      "path", Path.to_yojson path;
      "source", Source.to_yojson source;
    ]

let location_of_yojson json =
  let open Result.Syntax in
  match%bind Json.Decode.(fieldWith ~name:"type" string json) with
  | "link" ->
    let%bind path =
      Json.Decode.fieldWith
        ~name:"path"
        Path.of_yojson
        json
    in
    let%bind manifest =
      Json.Decode.fieldWith
        ~name:"manifest"
        (Json.Decode.nullable ManifestSpec.Filename.of_yojson )
        json
    in
    return (Link {path; manifest;})
  | "install" ->
    let%bind path =
      Json.Decode.fieldWith
        ~name:"path"
        Path.of_yojson
        json
    in
    let%bind source =
      Json.Decode.fieldWith
        ~name:"source"
        Source.of_yojson
        json
    in
    return (Install {path; source;})
  | typ -> errorf "unknown package type %s" typ

type t =
  location PackageId.Map.t
  [@@deriving yojson]

let empty = PackageId.Map.empty
let add = PackageId.Map.add

let mem = PackageId.Map.mem
let find = PackageId.Map.find_opt
let findExn = PackageId.Map.find
let entries = PackageId.Map.bindings

let ofPath path =
  let open RunAsync.Syntax in
  if%bind Fs.exists path
  then
    let%bind json = Fs.readJsonFile path in
    let%bind installation = RunAsync.ofRun (Json.parseJsonWith of_yojson json) in
    return (Some installation)
  else
    return None

let toPath path installation =
  let json = to_yojson installation in
  Fs.writeJsonFile ~json path
