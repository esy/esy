type t = {
  name : string;
  version : Version.t;
  digest : string option;
} [@@deriving ord]

let make name version digest =
  let digest =
    match digest with
    | Some digest ->
      let digest = Digestv.toHex digest in
      let digest = String.sub digest 0 8 in
      Some digest
    | None -> None
  in
  {name; version; digest}
let name {name; _} = name
let version {version; _} = version

let parse v =
  let open Result.Syntax in
  let split v = Astring.String.cut ~sep:"@" v in
  let rec parseName v =
    let open Result.Syntax in
    match split v with
    | Some ("", name) ->
      let%bind name, version = parseName name in
      return ("@" ^ name, version)
    | Some (name, version) ->
      return (name, version)
    | None -> error "invalid id: missing version"
  in
  let%bind name, v = parseName v in
  match split v with
  | Some (version, digest) ->
    let%bind version = Version.parse version in
    return {name; version; digest = Some digest;}
  | None ->
    let%bind version = Version.parse v in
    return {name; version; digest = None;}

let show {name; version; digest;} =
  match digest with
  | Some digest -> name ^ "@" ^ Version.show version ^ "@" ^ digest
  | None -> name ^ "@" ^ Version.show version

let pp fmt id = Fmt.pf fmt "%s" (show id)

let ppNoHash fmt id = Fmt.pf fmt "%s" (id.name ^ "@" ^ Version.show id.version)

let to_yojson id =
  `String (show id)

let of_yojson = function
  | `String v -> parse v
  | _ -> Error "expected string"

module Set = struct
  include Set.Make(struct
    type nonrec t = t
    let compare = compare
  end)

  let to_yojson set =
    let f el elems = (to_yojson el)::elems in
    `List (fold f set [])

  let of_yojson json =
    let elems =
      match json with
      | `List elems -> Result.List.map ~f:of_yojson elems
      | _ -> Error "expected array"
    in
    Result.map ~f:of_list elems
end

module Map = struct
  include Map.Make(struct
    type nonrec t = t
    let compare = compare
  end)

  let to_yojson v_to_yojson map =
    let items =
      let f id v items =
        let k = show id in
        (k, v_to_yojson v)::items
      in
      fold f map []
    in
    `Assoc items

  let of_yojson v_of_yojson =
    let open Result.Syntax in
    function
    | `Assoc items ->
      let f map (k, v) =
        let%bind k = parse k in
        let%bind v = v_of_yojson v in
        return (add k v map)
      in
      Result.List.foldLeft ~f ~init:empty items
    | _ -> error "expected an object"
end
