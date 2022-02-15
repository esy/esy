open EsyPackageConfig;

type location = Path.t;

let location_to_yojson = Path.to_yojson;

let location_of_yojson = Path.of_yojson;

let show_location = Path.show;
let pp_location = Path.pp;

[@deriving yojson]
type t = PackageId.Map.t(location);

let pp = PackageId.Map.pp(Path.pp);

let empty = PackageId.Map.empty;
let add = PackageId.Map.add;

let mem = PackageId.Map.mem;
let find = PackageId.Map.find_opt;
let findExn = PackageId.Map.find;
let entries = PackageId.Map.bindings;

let ofPath = path => {
  open RunAsync.Syntax;
  if%bind (Fs.exists(path)) {
    let* json = Fs.readJsonFile(path);
    let* installation = RunAsync.ofRun(Json.parseJsonWith(of_yojson, json));
    return(Some(installation));
  } else {
    return(None);
  };
};

let toPath = (path, installation) => {
  let json = to_yojson(installation);
  Fs.writeJsonFile(~json, path);
};
