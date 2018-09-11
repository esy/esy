type t = {
  path : Path.t;
  manifest : SandboxSpec.ManifestSpec.t option;
} [@@deriving yojson]

let ofFile path =
  let open RunAsync.Syntax in
  let%bind data = Fs.readFile path in
  match Yojson.Safe.from_string data with
  | json ->
    RunAsync.ofRun (Json.parseJsonWith of_yojson json)
  | exception Yojson.Json_error _ ->
    (* in case we can't parse JSON assume this is old style format where only
       path is specified on a line. *)
    let path = Path.v (String.trim data) in
    return {path; manifest = None}

let toFile file path =
  let json = to_yojson file in
  Fs.writeJsonFile ~json path
