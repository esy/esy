type t = Req.t list [@@deriving ord]

let empty = []

let pp fmt deps =
  Fmt.pf fmt "@[<h>%a@]" (Fmt.list ~sep:(Fmt.unit ", ") Req.pp) deps

let of_yojson json =
  let open Result.Syntax in
  let%bind items = Json.Decode.assoc json in
  let f deps (name, json) =
    let%bind spec = Json.Decode.string json in
    let%bind req = Req.parse (name ^ "@" ^ spec) in
    return (req::deps)
  in
  Result.List.foldLeft ~f ~init:empty items

let to_yojson (reqs : t) =
  let items =
    let f (req : Req.t) = (req.name, VersionSpec.to_yojson req.spec) in
    List.map ~f reqs
  in
  `Assoc items

let override deps update =
  let map =
    let f map (req : Req.t) = StringMap.add req.name req map in
    let map = StringMap.empty in
    let map = List.fold_left ~f ~init:map deps in
    let map = List.fold_left ~f ~init:map update in
    map
  in
  StringMap.values map

let find ~name reqs =
  let f (req : Req.t) = req.name = name in
  List.find_opt ~f reqs

module Override = struct
  type t = Req.t StringMap.Override.t [@@deriving ord, show]

  let of_yojson =
    let req_of_yojson name json =
      let open Result.Syntax in
      let%bind spec = Json.Decode.string json in
      Req.parse (name ^ "@" ^ spec)
    in
    StringMap.Override.of_yojson req_of_yojson

  let to_yojson =
    let req_to_yojson req =
      VersionSpec.to_yojson req.Req.spec
    in
    StringMap.Override.to_yojson req_to_yojson
end


