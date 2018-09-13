module ManifestSpec = struct
  type t =
  | Esy of string
  | Opam of string
  | OpamAggregated of string list
  [@@deriving ord, eq]

  let toString = function
    | Esy fname | Opam fname -> fname
    | OpamAggregated fnames -> String.concat "," fnames

  let show = toString

  let pp fmt manifest =
    match manifest with
    | Esy fname | Opam fname -> Fmt.string fmt fname
    | OpamAggregated fnames -> Fmt.(list ~sep:(unit ", ") string) fmt fnames

  let ofString fname =
    (* this deliberately doesn't handle OpamAggregated *)
    let open Result.Syntax in
    match fname with
    | "" -> errorf "empty filename"
    | "opam" -> return (Opam "opam")
    | fname ->
      begin match Path.(getExt (v fname)) with
      | ".json" -> return (Esy fname)
      | ".opam" -> return (Opam fname)
      | _ -> errorf "invalid manifest: %s" fname
      end

  let ofStringExn fname =
    match ofString fname with
    | Ok fname -> fname
    | Error msg -> failwith msg

  let parser =
    let make fname =
      match ofString fname with
      | Ok fname -> Parse.return fname
      | Error msg -> Parse.fail msg
    in
    Parse.(take_while1 (fun _ -> true) >>= make)

  let to_yojson manifest =
    match manifest with
    | Esy fname | Opam fname -> `String fname
    | OpamAggregated fnames ->
      let fnames = List.map ~f:(fun fname -> `String fname) fnames in
      `List fnames

  let of_yojson json =
    let open Result.Syntax in
    match json with
    | `String "opam" -> return (Opam "opam")
    | `String fname -> ofString fname
    | `List fnames ->
      let%bind fnames =
        let f json =
          match json with
          | `String fname ->
            begin match Path.(getExt (v fname)) with
            | ".json" -> return fname
            | _ -> errorf "invalid opam manifest: %s" fname
            end
          | _ -> errorf "expected string"
        in
        Result.List.map ~f fnames
      in
      return (OpamAggregated fnames)
    | _ -> errorf "invalid manifest"

  module Set = Set.Make(struct
    type nonrec t = t
    let compare = compare
  end)

  module Map = Map.Make(struct
    type nonrec t = t
    let compare = compare
  end)
end

type t = {
  path : Path.t;
  manifest : ManifestSpec.t
} [@@deriving ord, eq]

let doesPathReferToConcreteManifest path =
  Path.(
    hasExt ".json" path
    || hasExt ".opam" path
    || Path.(equal path (v "opam"))
  )

let name spec =
  match spec.manifest with
  | OpamAggregated _ -> "opam"
  | Opam "opam" -> "opam"
  | Esy "package.json" | Esy "esy.json" -> "default"
  | Opam fname | Esy fname -> Path.(show (remExt (v fname)))

let isDefault spec =
  match spec.manifest with
  | Esy "package.json" -> true
  | Esy "esy.json" -> true
  | _ -> false

let localPrefixPath spec =
  let name = name spec in
  Path.(spec.path / "_esy" / name)

let nodeModulesPath spec = Path.(localPrefixPath spec / "node_modules")
let cachePath spec = Path.(localPrefixPath spec / "cache")
let storePath spec = Path.(localPrefixPath spec / "store")
let buildPath spec = Path.(localPrefixPath spec / "build")

let lockfilePath spec =
  match spec.manifest with
  | Esy "package.json" | Esy "esy.json" -> Path.(spec.path / "esy.lock.json")
  | _ ->
    let name = name spec in
    Path.(spec.path / ("esy." ^ name ^ ".json"))

let ofPath path =
  let open RunAsync.Syntax in

  let discoverOfDir path =
    let%bind fnames = Fs.listDir path in
    let fnames = StringSet.of_list fnames in

    let%bind manifest =
      if StringSet.mem "esy.json" fnames
      then return (ManifestSpec.Esy "esy.json")
      else if StringSet.mem "package.json" fnames
      then return (ManifestSpec.Esy "package.json")
      else
        let opamFnames =
          let isOpamFname fname = Path.(hasExt ".opam" (v fname)) || fname = "opam" in
          List.filter ~f:isOpamFname (StringSet.elements fnames)
        in
        begin match opamFnames with
        | [] -> errorf "no manifests found at %a" Path.pp path
        | [fname] -> return (ManifestSpec.Opam fname)
        | fnames -> return (ManifestSpec.OpamAggregated fnames)
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
            return {path = sandboxPath; manifest = Opam fname}
          else
            match Path.getExt fpath with
            | ".json" -> return {path = sandboxPath; manifest = Esy fname}
            | ".opam" -> return {path = sandboxPath; manifest = Opam fname}
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
