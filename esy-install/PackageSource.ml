module OpamName = struct
  type t = OpamPackage.Name.t
  let to_yojson name = `String (OpamPackage.Name.to_string name)
  let of_yojson = function
    | `String name -> Ok (OpamPackage.Name.of_string name)
    | _ -> Error "expected string"
end

module OpamVersion = struct
  type t = OpamPackage.Version.t
  let to_yojson name = `String (OpamPackage.Version.to_string name)
  let of_yojson = function
    | `String name -> Ok (OpamPackage.Version.of_string name)
    | _ -> Error "expected string"
end

type opam = {
  name : OpamName.t;
  version : OpamVersion.t;
  path : Path.t;
} [@@deriving yojson]

let opamfiles opam =
  File.ofDir Path.(opam.path / "files")

type t =
  | Link of Dist.local
  | Install of {
      source : Dist.t * Dist.t list;
      opam : opam option;
    }

let to_yojson source =
  let open Json.Encode in
  match source with
  | Link { path; manifest } ->
    assoc [
      field "type" string "link";
      field "path" DistPath.to_yojson path;
      fieldOpt "manifest" ManifestSpec.to_yojson manifest;
    ]
  | Install { source = source, mirrors; opam } ->
    assoc [
      field "type" string "install";
      field "source" (Json.Encode.list Dist.to_yojson) (source::mirrors);
      fieldOpt "opam" opam_to_yojson opam;
    ]

let of_yojson json =
  let open Result.Syntax in
  let open Json.Decode in
  match%bind fieldWith ~name:"type" string json with
  | "install" ->
    let%bind source =
      match%bind fieldWith ~name:"source" (list Dist.of_yojson) json with
      | source::mirrors -> return (source, mirrors)
      | _ -> errorf "invalid source configuration"
    in
    let%bind opam = fieldOptWith ~name:"opam" opam_of_yojson json in
    Ok (Install {source; opam;})
  | "link" ->
    let%bind path = fieldWith ~name:"path" DistPath.of_yojson json in
    let%bind manifest = fieldOptWith ~name:"manifest" ManifestSpec.of_yojson json in
    Ok (Link {path; manifest;})
  | typ -> errorf "unknown source type: %s" typ

