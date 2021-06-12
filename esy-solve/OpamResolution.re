open EsyPackageConfig;

[@deriving yojson]
type t = PackageSource.opam;

let make = (name, version, path) => {PackageSource.name, version, path};

let name = ({PackageSource.name, _}) => OpamPackage.Name.to_string(name);
let version = ({PackageSource.version, _}) => Version.Opam(version);
let path = ({PackageSource.path, _}) => path;

let opam = (res: PackageSource.opam) => {
  open RunAsync.Syntax;
  let path = Path.(res.path / "opam");
  let* data = Fs.readFile(path);
  let filename = OpamFile.make(OpamFilename.of_string(Path.show(path)));
  try(return(OpamFile.OPAM.read_from_string(~filename, data))) {
  | Failure(msg) =>
    errorf("error parsing opam metadata %a: %s", Path.pp, path, msg)
  | _ => error("error parsing opam metadata")
  };
};

let files = (res: PackageSource.opam) =>
  File.ofDir(Path.(res.path / "files"));

let digest = (res: PackageSource.opam) => {
  open RunAsync.Syntax;
  let* files = files(res);
  let* digests = RunAsync.List.mapAndJoin(~f=File.digest, files);
  let* digest = Digestv.ofFile(Path.(res.path / "opam"));
  let digests = [digest, ...digests];
  let digests = List.sort(~cmp=Digestv.compare, digests);
  return(List.fold_left(~init=Digestv.empty, ~f=Digestv.combine, digests));
};
