type t = {
  path : Path.t;
  manifest : ManifestSpec.t
} [@@deriving ord]

let doesPathReferToConcreteManifest path =
  Path.(
    hasExt ".json" path
    || hasExt ".opam" path
    || Path.(compare path (v "opam") = 0)
  )

let projectName spec =
  let nameOfPath spec = Path.basename spec.path in
  match spec.manifest with
  | ManyOpam -> nameOfPath spec
  | One (Opam, "opam") -> nameOfPath spec
  | One (Esy, "package.json") | One (Esy, "esy.json") -> nameOfPath spec
  | One (_, fname) -> Path.(show (remExt (v fname)))

let name spec =
  match spec.manifest with
  | ManyOpam -> "opam"
  | One (Opam, "opam") -> "opam"
  | One (Esy, "package.json") | One (Esy, "esy.json") -> "default"
  | One (_, fname) -> Path.(show (remExt (v fname)))

let isDefault spec =
  match spec.manifest with
  | One (Esy, "package.json") -> true
  | One (Esy, "esy.json") -> true
  | _ -> false

let localPrefixPath spec =
  let name = name spec in
  Path.(spec.path / "_esy" / name)

let installationPath spec = Path.(localPrefixPath spec / "installation.json")
let pnpJsPath spec = Path.(localPrefixPath spec / "pnp.js")
let nodeModulesPath spec = Path.(localPrefixPath spec / "node_modules")
let cachePath spec = Path.(localPrefixPath spec / "cache")
let storePath spec = Path.(localPrefixPath spec / "store")
let buildPath spec = Path.(localPrefixPath spec / "build")
let binPath spec = Path.(localPrefixPath spec / "bin")

let lockfilePath spec =
  match spec.manifest with
  | One (Esy, "package.json")
  | One (Esy, "esy.json") -> Path.(spec.path / "esy.lock")
  | _ -> Path.(spec.path / (name spec ^ ".esy.lock"))

let ofPath path =
  let open RunAsync.Syntax in

  let discoverOfDir path =
    let%bind fnames = Fs.listDir path in
    let fnames = StringSet.of_list fnames in

    let%bind manifest =
      if StringSet.mem "esy.json" fnames
      then return (ManifestSpec.One (Esy, "esy.json"))
      else if StringSet.mem "package.json" fnames
      then return (ManifestSpec.One (Esy, "package.json"))
      else
        let opamFnames =
          let isOpamFname fname = Path.(hasExt ".opam" (v fname)) || fname = "opam" in
          List.filter ~f:isOpamFname (StringSet.elements fnames)
        in
        begin match opamFnames with
        | [] -> errorf "no manifests found at %a" Path.pp path
        | [fname] -> return (ManifestSpec.One (Opam, fname))
        | _fnames -> return ManifestSpec.ManyOpam
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
            return {path = sandboxPath; manifest = One (Opam, fname);}
          else
            match Path.getExt fpath with
            | ".json" -> return {path = sandboxPath; manifest = One (Esy, fname);}
            | ".opam" -> return {path = sandboxPath; manifest = One (Opam, fname);}
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
  ManifestSpec.pp fmt spec.manifest

let show spec = Format.asprintf "%a" pp spec

module Set = Set.Make(struct
  type nonrec t = t
  let compare = compare
end)

module Map = Map.Make(struct
  type nonrec t = t
  let compare = compare
end)
