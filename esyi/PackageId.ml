type t = string * Version.t [@@deriving ord]

let make name version = name, version
let name (name, _version) = name
let version (_name, version) = version

let rec parse v =
  let open Result.Syntax in
  match Astring.String.cut ~sep:"@" v with
  | Some ("", name) ->
    let%bind name, version = parse name in
    return ("@" ^ name, version)
  | Some (name, version) ->
    let%bind version = Version.parse version in
    return (name, version)
  | None -> Error "invalid id"

let show (name, version) = name ^ "@" ^ Version.show version
let pp fmt id = Fmt.pf fmt "%s" (show id)

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
      let f (name, version) v items =
        let k = name ^ "@" ^ Version.show version in
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
