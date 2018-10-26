module OpamPackageName = struct
  type t = OpamPackage.Name.t
  let to_yojson name = `String (OpamPackage.Name.to_string name)
  let of_yojson = function
    | `String name -> Ok (OpamPackage.Name.of_string name)
    | _ -> Error "expected string"
end

module OpamPackageVersion = struct
  type t = OpamPackage.Version.t
  let to_yojson name = `String (OpamPackage.Version.to_string name)
  let of_yojson = function
    | `String name -> Ok (OpamPackage.Version.of_string name)
    | _ -> Error "expected string"
end

type t = {
  name : OpamPackageName.t;
  version : OpamPackageVersion.t;
  path : Path.t;
} [@@deriving yojson]
