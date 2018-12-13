module OpamPackage_Name = struct
  type t = OpamPackage.Name.t
  let to_yojson name = `String (OpamPackage.Name.to_string name)
  let of_yojson = function
    | `String name -> Ok (OpamPackage.Name.of_string name)
    | _ -> Error "expected string"
end

module OpamPackage_Version = struct
  type t = OpamPackage.Version.t
  let to_yojson name = `String (OpamPackage.Version.to_string name)
  let of_yojson = function
    | `String name -> Ok (OpamPackage.Version.of_string name)
    | _ -> Error "expected string"
end

type t = {
  name : OpamPackage_Name.t;
  version : OpamPackage_Version.t;
  path : Path.t;
} [@@deriving yojson]

let make name version path =
  {name; version; path;}

let name {name;_} = OpamPackage.Name.to_string name
let version {version;_} = Version.Opam version
let path {path;_} = path

let opam res =
  let open RunAsync.Syntax in
  let path = Path.(res.path / "opam") in
  let%bind data = Fs.readFile path in
  let filename = OpamFile.make (OpamFilename.of_string (Path.show path)) in
  try return (OpamFile.OPAM.read_from_string ~filename data) with
  | Failure msg -> errorf "error parsing opam metadata %a: %s" Path.pp path msg
  | _ -> error "error parsing opam metadata"

let files res = File.ofDir Path.(res.path / "files")

let digest res =
  let open RunAsync.Syntax in
  let%bind files = files res in
  let%bind digests = RunAsync.List.mapAndJoin ~f:File.digest files in
  let%bind digest = Digestv.ofFile Path.(res.path / "opam") in
  let digests = digest::digests in
  let digests = List.sort ~cmp:Digestv.compare digests in
  return (List.fold_left ~init:Digestv.empty ~f:Digestv.combine digests)

let toLock ~sandbox opam =
  let open RunAsync.Syntax in
  let sandboxPath = sandbox.SandboxSpec.path in
  let opampath = Path.(sandboxPath // opam.path) in
  let dst =
    let name = OpamPackage.Name.to_string opam.name in
    let version = OpamPackage.Version.to_string opam.version in
    Path.(SandboxSpec.solutionLockPath sandbox / "opam" / (name ^ "." ^ version))
  in
  if Path.isPrefix sandboxPath opampath
  then return opam
  else (
    let%bind () = Fs.copyPath ~src:opam.path ~dst in
    return {opam with path = Path.tryRelativize ~root:sandboxPath dst;}
  )

let ofLock ~sandbox opam =
  let open RunAsync.Syntax in
  let sandboxPath = sandbox.SandboxSpec.path in
  let opampath = Path.(sandboxPath // opam.path) in
  return {opam with path = opampath;}
