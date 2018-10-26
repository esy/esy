module P = Package
module Package = struct

  module Opam = struct
    type t = {
      name : Package.Opam.OpamName.t;
      version : Package.Opam.OpamPackageVersion.t;
      opam : Package.Opam.OpamFile.t;
      override : Package.Overrides.override option;
    } [@@deriving yojson]
  end

  module SourceWithMirrors = struct
    type t = Source.t * Source.t list

    let to_yojson = function
      | main, [] -> Source.to_yojson main
      | main, mirrors -> `List (List.map ~f:Source.to_yojson (main::mirrors))

    let of_yojson (json : Json.t) =
      let open Result.Syntax in
      match json with
      | `String _ ->
        let%bind source = Source.of_yojson json in
        return (source, [])
      | `List _ ->
        begin match%bind Json.Decode.list Source.of_yojson json with
        | main::mirrors -> return (main, mirrors)
        | [] -> error "expected a non empty array or a string"
        end
      | _ -> error "expected a non empty array or a string"

  end

  type t = {
    name: string;
    version: Version.t;
    source: source;
    overrides: Package.Overrides.t;
    dependencies : PackageId.Set.t;
    devDependencies : PackageId.Set.t;
  } [@@deriving yojson]

  and source =
    | Link of {
        path : Path.t;
        manifest : ManifestSpec.t option;
      }
    | Install of {
        source : SourceWithMirrors.t;
        files : Package.File.t list;
        opam : Opam.t option;
      }

  let id r = PackageId.make r.name r.version

  let compare a b =
    PackageId.compare (id a) (id b)

  let pp fmt pkg =
    Fmt.pf fmt "%s@%a" pkg.name Version.pp pkg.version

  let show = Format.asprintf "%a" pp

  module Map = Map.Make(struct type nonrec t = t let compare = compare end)
  module Set = Set.Make(struct type nonrec t = t let compare = compare end)
end

let traverse pkg =
  pkg.Package.dependencies |> PackageId.Set.elements

let traverseWithDevDependencies pkg =
  PackageId.Set.union pkg.Package.dependencies pkg.Package.devDependencies
  |> PackageId.Set.elements

include Graph.Make(struct
  include Package
  let traverse = traverse
  module Id = PackageId
end)
