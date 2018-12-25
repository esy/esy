open EsyPackageConfig

type t = PackageSource.opam [@@deriving yojson]

let make name version path =
  {PackageSource.name; version; path;}

let name {PackageSource.name;_} = OpamPackage.Name.to_string name
let version {PackageSource.version;_} = Version.Opam version
let path {PackageSource.path;_} = path

let opam (res : PackageSource.opam) =
  let open RunAsync.Syntax in
  let path = Path.(res.path / "opam") in
  let%bind data = Fs.readFile path in
  let filename = OpamFile.make (OpamFilename.of_string (Path.show path)) in
  try return (OpamFile.OPAM.read_from_string ~filename data) with
  | Failure msg -> errorf "error parsing opam metadata %a: %s" Path.pp path msg
  | _ -> error "error parsing opam metadata"

let files (res : PackageSource.opam) = File.ofDir Path.(res.path / "files")

let digest (res : PackageSource.opam) =
  let open RunAsync.Syntax in
  let%bind files = files res in
  let%bind digests = RunAsync.List.mapAndJoin ~f:File.digest files in
  let%bind digest = Digestv.ofFile Path.(res.path / "opam") in
  let digests = digest::digests in
  let digests = List.sort ~cmp:Digestv.compare digests in
  return (List.fold_left ~init:Digestv.empty ~f:Digestv.combine digests)
