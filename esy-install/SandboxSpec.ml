open EsyPackageConfig

type t = {
  path : Path.t;
  manifest : manifest;
} [@@deriving ord, yojson]

and manifest =
  | Manifest of ManifestSpec.t
  | ManifestAggregate of ManifestSpec.t list

let projectName spec =
  let nameOfPath spec = Path.basename spec.path in
  match spec.manifest with
  | ManifestAggregate _ -> nameOfPath spec
  | Manifest (Opam, "opam") -> nameOfPath spec
  | Manifest (Esy, "package.json")
  | Manifest (Esy, "esy.json") -> nameOfPath spec
  | Manifest (_, fname) -> Path.(show (remExt (v fname)))

let name spec =
  match spec.manifest with
  | ManifestAggregate _
  | Manifest (Opam, "opam")
  | Manifest (Esy, "package.json")
  | Manifest (Esy, "esy.json") -> "default"
  | Manifest (_, fname) -> Path.(show (remExt (v fname)))

let isDefault spec =
  match spec.manifest with
  | Manifest (Esy, "package.json") -> true
  | Manifest (Esy, "esy.json") -> true
  | _ -> false

let localPrefixPath spec =
  let name = name spec in
  Path.(spec.path / "_esy" / name)

let manifestPaths spec =
  match spec.manifest with
  | Manifest (_kind, filename) ->
    [Path.(spec.path / filename)]
  | ManifestAggregate filenames ->
    List.map
      ~f:(fun (_kind, filename) -> Path.(spec.path / filename))
      filenames

let installationPath spec = Path.(localPrefixPath spec / "installation.json")
let pnpJsPath spec = Path.(localPrefixPath spec / "pnp.js")
let cachePath spec = Path.(localPrefixPath spec / "cache")
let storePath spec = Path.(localPrefixPath spec / "store")
let buildPath spec = Path.(localPrefixPath spec / "build")
let binPath spec = Path.(localPrefixPath spec / "bin")
let distPath spec = Path.(localPrefixPath spec / "dist")
let tempPath spec = Path.(localPrefixPath spec / "tmp")

let solutionLockPath spec =
  match spec.manifest with
  | ManifestAggregate _
  | Manifest (Opam, "opam")
  | Manifest (Esy, "package.json")
  | Manifest (Esy, "esy.json") -> Path.(spec.path / "esy.lock")
  | _ -> Path.(spec.path / (name spec ^ ".esy.lock"))

let ofPath path =
  let open RunAsync.Syntax in

  let discoverOfDir path =
    let%bind fnames = Fs.listDir path in
    let fnames = StringSet.of_list fnames in

    let%bind manifest =
      if StringSet.mem "esy.json" fnames
      then return (Manifest (Esy, "esy.json"))
      else if StringSet.mem "package.json" fnames
      then return (Manifest (Esy, "package.json"))
      else if StringSet.mem "opam" fnames
      then return (Manifest (Opam, "opam"))
      else
        let%bind filenames =
          let f filename =
            let path = Path.(path / filename) in
            if Path.(hasExt ".opam" path)
            then
              let%bind data = Fs.readFile path in
              return (String.(length (trim data)) > 0)
            else
              return false
          in
          RunAsync.List.filter ~f (StringSet.elements fnames)
        in
        begin match filenames with
        | [] -> errorf "no manifests found at %a" Path.pp path
        | [filename] -> return (Manifest (Opam, filename))
        | filenames ->
          let filenames = List.map ~f:(fun fn -> ManifestSpec.Opam, fn) filenames in
          return (ManifestAggregate filenames)
        end
    in
    return {path; manifest}
  in

  let ofFile path =
    let sandboxPath = Path.(remEmptySeg (parent path)) in

    let rec tryLoad = function
      | [] -> errorf "cannot load sandbox manifest at: %a" Path.pp path
      | fname::rest ->
        let fpath = Path.(sandboxPath / fname) in
        if%bind Fs.exists fpath
        then (
          if fname = "opam"
          then
            return {path = sandboxPath; manifest = Manifest (Opam, fname);}
          else
            match Path.getExt fpath with
            | ".json" -> return {path = sandboxPath; manifest = Manifest (Esy, fname);}
            | ".opam" -> return {path = sandboxPath; manifest = Manifest (Opam, fname);}
            | _ -> tryLoad rest
        ) else
          tryLoad rest
    in
    let fname = Path.basename path in
    tryLoad [fname; fname ^ ".json"; fname ^ ".opam";]
  in

  if%bind Fs.isDir path
  then discoverOfDir path
  else ofFile path

let pp fmt spec =
  match spec.manifest with
  | Manifest filename ->
    ManifestSpec.pp fmt filename
  | ManifestAggregate filenames ->
    Fmt.(list ~sep:(unit ", ") ManifestSpec.pp) fmt filenames

let show spec = Format.asprintf "%a" pp spec

module Set = Set.Make(struct
  type nonrec t = t
  let compare = compare
end)

module Map = Map.Make(struct
  type nonrec t = t
  let compare = compare
end)
