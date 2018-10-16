type location = Path.t

let location_to_yojson = Path.to_yojson

let location_of_yojson = Path.of_yojson

let show_location = Path.show
let pp_location = Path.pp

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
