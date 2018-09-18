type t = {
  source : Source.t;
  override : Package.Override.t option [@default None];
} [@@deriving yojson]

let ofFile path =
  let open RunAsync.Syntax in
  let%bind json = Fs.readJsonFile path in
  RunAsync.ofRun (Json.parseJsonWith of_yojson json)

let toFile file path =
  let json = to_yojson file in
  Fs.writeJsonFile ~json path

let ofDir path =
  let open RunAsync.Syntax in
  let fname = Path.(path / "_esylink") in
  if%bind Fs.exists fname
  then
    ofFile fname
  else
    (* If not _esylink file found in the directory we synthesize one which links
     * sources from the directory. This allows to just copy some package into
     * node_modules without invoking 'esy install' command.
     *)
    return {
      source = Source.LocalPathLink {path; manifest = None};
      override = None;
    }

let toDir file path =
  toFile file Path.(path / "_esylink")
