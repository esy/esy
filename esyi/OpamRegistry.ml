module Version = OpamVersion.Version
module VersionMap = Map.Make(Version)
module String = Astring.String

let filterNone items =
  let rec aux items = function
    | [] -> items
    | None::rest -> aux items rest
    | (Some item)::rest -> aux (item::items) rest
  in
  List.rev (aux [] items)

module OpamPathsByVersion = Memoize.Make(struct
  type key = string
  type value = Path.t VersionMap.t RunAsync.t
end)

let versionIndexCache =
  OpamPathsByVersion.make ()

let getVersionIndex ~cfg name =
  let f name =
    let open RunAsync.Syntax in
    let opamName = OpamFile.withoutScope name in
    let path = Path.(cfg.Config.opamRepositoryPath / "packages" / opamName) in
    let%bind entries = Fs.listDir path in
    let f index entry =
      let version = match String.cut ~sep:"." entry with
        | None -> Version.parseExn ""
        | Some (_name, version) -> Version.parseExn version
      in
      VersionMap.add version Path.(path / entry) index
    in
    return (ListLabels.fold_left ~init:VersionMap.empty ~f entries)
  in
  OpamPathsByVersion.compute versionIndexCache name f

let getThinManifest ~cfg name (version : Version.t) =
  let open RunAsync.Syntax in
  let%bind index = getVersionIndex ~cfg name in
  match VersionMap.find_opt version index with
  | None -> return None
  | Some packagePath ->
    let manifest =
      let path = Path.(packagePath / "opam") in
      let opamFile = OpamParser.file (Path.toString path) in
      let opamName = OpamFile.withoutScope name in
      OpamFile.parseManifest (opamName, version) opamFile
    in
    if not manifest.OpamFile.available
    then return None
    else
      let opamFile = Path.(packagePath / "opam") in
      let urlFile = Path.(packagePath / "url") in
      let manifest = {
        OpamFile.ThinManifest.
        name = name;
        opamFile;
        urlFile;
        version
      } in
    return (Some manifest)

let versions ~cfg name =
  let open RunAsync.Syntax in
  let%bind index = getVersionIndex ~cfg name in
  let%bind items =
    index
    |> VersionMap.bindings
    |> List.map (fun (version, _path) -> getThinManifest ~cfg name version)
    |> RunAsync.List.joinAll
  in
  return (
    items
    |> filterNone
    |> List.map (fun manifest -> (manifest.OpamFile.ThinManifest.version, manifest))
  )

let version ~cfg ~opamOverrides name version =
  let open RunAsync.Syntax in
  match%bind getThinManifest ~cfg name version with
  | None -> return None
  | Some { OpamFile.ThinManifest. opamFile; urlFile; name; version } ->
    let%bind source =
      if%bind Fs.exists urlFile
      then return (OpamFile.parseUrlFile (OpamParser.file (Path.toString urlFile)))
      else return PackageInfo.Source.NoSource
    in
    let opamName = OpamFile.withoutScope name in
    let manifest =
      let manifest =
        OpamFile.parseManifest (opamName, version) (OpamParser.file (Path.toString opamFile))
      in
      {manifest with source}
    in
    begin match%bind OpamOverrides.findApplicableOverride opamOverrides opamName version with
      | None ->
        return (Some manifest)
      | Some override ->
        let manifest = OpamOverrides.applyOverride manifest override in
        return (Some manifest)
    end
