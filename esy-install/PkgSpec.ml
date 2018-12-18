type t =
  | Root
  | ByName of string
  | ByNameVersion of (string * Version.t)
  | ById of PackageId.t

let pp fmt = function
  | Root -> Fmt.unit "root" fmt ()
  | ByName name -> Fmt.string fmt name
  | ByNameVersion (name, version) -> Fmt.pf fmt "%s@%a" name Version.pp version
  | ById id -> PackageId.pp fmt id

let matches rootid pkgspec pkgid =
  match pkgspec with
  | Root -> PackageId.compare rootid pkgid = 0
  | ByName name -> String.compare name (PackageId.name pkgid) = 0
  | ByNameVersion (name, version) ->
    String.compare name (PackageId.name pkgid) = 0
    && Version.compare version (PackageId.version pkgid) = 0
  | ById id -> PackageId.compare id pkgid = 0

let parse =
  let open Result.Syntax in
  function
  | "root" -> return Root
  | v ->
    let split = Astring.String.cut ~sep:"@" in
    let rec parsename v =
      match split v with
      | Some ("", v) ->
        let name, rest = parsename v in
        "@" ^ name, rest
      | Some (name, rest) ->
        name, Some rest
      | None -> v, None
    in
    match parsename v with
    | name, Some ""
    | name, None -> return (ByName name)
    | name, Some rest ->
      begin match split rest with
      | Some _ ->
        let%bind id = PackageId.parse v in
        return (ById id)
      | None ->
        let%bind version = Version.parse rest in
        return (ByNameVersion (name, version))
      end

let of_yojson json =
  match json with
  | `String v -> parse v
  | _ -> Error "PkgSpec: expected a string"
