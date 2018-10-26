module P = Package

module File = P.File

module Package = struct

  type t = {
    name: string;
    version: Version.t;
    source: Package.source;
    overrides: Package.Overrides.t;
    dependencies : PackageId.Set.t;
    devDependencies : PackageId.Set.t;
  } [@@deriving yojson]

  type opam = {
    opamname : OpamPackage.Name.t;
    opamversion : OpamPackage.Version.t;
    opamfile : OpamFile.OPAM.t;
  }

  let id r = PackageId.make r.name r.version

  let compare a b =
    PackageId.compare (id a) (id b)

  let pp fmt pkg =
    Fmt.pf fmt "%s@%a" pkg.name Version.pp pkg.version

  let show = Format.asprintf "%a" pp

  let readOpam pkg =
    let open RunAsync.Syntax in
    match pkg.source with
    | P.Install { opam = Some opam; _ } ->
      let path = Path.(opam.path / "opam" |> show) in
      let filename = OpamFile.make (OpamFilename.of_string "opam") in
      let opamfile = OpamFile.OPAM.read_from_string ~filename path in
      return (Some {
        opamname = opam.name;
        opamversion = opam.version;
        opamfile;
      })
    | _ -> return None

  let readOpamFiles pkg =
    let open RunAsync.Syntax in
    match pkg.source with
    | P.Install { opam = Some opam; _ } ->
      let filesPath = Path.(opam.path / "files") in
      if%bind Fs.exists filesPath
      then
        let%bind files = Fs.listDir filesPath in
        let f filename =
          File.readOfPath
            ~prefixPath:filesPath
            ~filePath:Path.(filesPath / filename)
        in
        RunAsync.List.mapAndJoin ~f files
      else return []
    | _ -> return []

  module Map = Map.Make(struct type nonrec t = t let compare = compare end)
  module Set = Set.Make(struct type nonrec t = t let compare = compare end)
end

let traverse pkg =
  PackageId.Set.elements pkg.Package.dependencies

let traverseWithDevDependencies pkg =
  let dependencies =
    PackageId.Set.union
      pkg.Package.dependencies
      pkg.Package.devDependencies
  in
  PackageId.Set.elements dependencies

include Graph.Make(struct
  include Package
  let traverse = traverse
  module Id = PackageId
end)
