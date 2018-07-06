module Version = SemverVersion.Version
module String = Astring.String
module Resolutions = Package.Resolutions
module Source = Package.Source
module Req = Package.Req
module Dep = Package.Dep

module Dependencies = struct

  type t = Req.t list

  let empty = []

  let pp fmt deps =
    Fmt.pf fmt "@[<hov>[@;%a@;]@]" (Fmt.list ~sep:(Fmt.unit ", ") Req.pp) deps

  let of_yojson json =
    let open Result.Syntax in
    let%bind items = Json.Parse.assoc json in
    let f deps (name, json) =
      let%bind spec = Json.Parse.string json in
      let req = Req.make ~name ~spec in
      return (req::deps)
    in
    Result.List.foldLeft ~f ~init:empty items

  let to_yojson (deps : t) =
    let items =
      let f req = (req.Req.name, Req.to_yojson req) in
      List.map ~f deps
    in
    `Assoc items
end

(* This is used just to read the Json.t *)
module PackageJson = struct
  type t = {
    name : string;
    version : string;
    resolutions : (Resolutions.t [@default Resolutions.empty]);
    dependencies : (Dependencies.t [@default Dependencies.empty]);
    devDependencies : (Dependencies.t [@default Dependencies.empty]);
    dist : (dist option [@default None]);
    esy : (Json.t option [@default None]);
  } [@@deriving of_yojson { strict = false }]

  and dist = {
    tarball : string;
    shasum : string;
  }

  let ofFile (path : Path.t) =
    let open RunAsync.Syntax in
    let%bind data = Fs.readJsonFile path in
    let%bind pkgJson = RunAsync.ofRun (Json.parseJsonWith of_yojson data) in
    return pkgJson

  let ofDir (path : Path.t) =
    let open RunAsync.Syntax in
    let esyJson = Path.(path / "esy.json") in
    let packageJson = Path.(path / "package.json") in
    if%bind Fs.exists esyJson
    then ofFile esyJson
    else if%bind Fs.exists packageJson
    then ofFile packageJson
    else error "no package.json found"
end

type t = {
  name : string;
  version : string;
  dependencies : Dependencies.t;
  devDependencies : Dependencies.t;
  source : Source.t;
  hasEsyManifest : bool;
}

type manifest = t

let name manifest = manifest.name
let version manifest = Version.parseExn manifest.version

let ofPackageJson ?(source=Source.NoSource) (pkgJson : PackageJson.t) = {
  name = pkgJson.name;
  version = pkgJson.version;
  dependencies = pkgJson.dependencies;
  devDependencies = pkgJson.devDependencies;
  hasEsyManifest = Option.isSome pkgJson.esy;
  source =
    match pkgJson.dist with
    | Some dist -> Source.Archive (dist.PackageJson.tarball, dist.PackageJson.shasum)
    | None -> source;
}

let of_yojson json =
  let open Result.Syntax in
  let%bind pkgJson = PackageJson.of_yojson json in
  return (ofPackageJson pkgJson)

let ofDir (path : Path.t) =
  let open RunAsync.Syntax in
  let%bind pkgJson = PackageJson.ofDir path in
  return (ofPackageJson pkgJson)

module Root = struct
  type t = {
    manifest : manifest;
    resolutions : Resolutions.t;
  }

  let ofDir (path : Path.t) =
    let open RunAsync.Syntax in
    let%bind pkgJson = PackageJson.ofDir path in
    let manifest = ofPackageJson pkgJson in
    return {manifest; resolutions = pkgJson.PackageJson.resolutions}
end

let toPackage ?name ?version (manifest : t) =
  let open RunAsync.Syntax in
  let name =
    match name with
    | Some name -> name
    | None -> manifest.name
  in
  let version =
    match version with
    | Some version -> version
    | None -> Package.Version.Npm (SemverVersion.Version.parseExn manifest.version)
  in
  let source =
    match version with
    | Package.Version.Source src -> Package.Source src
    | _ -> Package.Source manifest.source
  in

  let translateDependencies reqs =
    let f reqs (req : Req.t) =
      let update =
        match req.spec with
        | Package.VersionSpec.Npm formula ->
          let f (c : SemverVersion.Constraint.t) =
            {Dep. name = req.name; req = Npm c}
          in
          let formula = SemverVersion.Formula.ofDnfToCnf formula in
          List.map ~f:(List.map ~f) formula
        | Package.VersionSpec.Opam formula ->
          let f (c : OpamVersion.Constraint.t) =
            {Dep. name = req.name; req = Opam c}
          in
          let formula = OpamVersion.Formula.ofDnfToCnf formula in
          List.map ~f:(List.map ~f) formula
        | Package.VersionSpec.Source spec ->
          [[{Dep. name = req.name; req = Source spec}]]
      in
      reqs @ update
    in
    List.fold_left ~f ~init:[] reqs
  in

  let pkg = {
    Package.
    name;
    version;
    dependencies = translateDependencies manifest.dependencies;
    devDependencies = translateDependencies manifest.devDependencies;
    source;
    opam = None;
    kind =
      if manifest.hasEsyManifest
      then Esy
      else Npm
  } in

  return pkg

