module PackageName = OpamFile.PackageName
module Version = OpamVersion.Version
module VersionMap = Map.Make(Version)
module String = Astring.String

module OpamPathsByVersion = Memoize.Make(struct
  type key = OpamFile.PackageName.t
  type value = Path.t VersionMap.t RunAsync.t
end)


type t = {
  repoPath : Path.t;
  overrides : OpamOverrides.t;
  pathsCache : OpamPathsByVersion.t;
  
}

let init ~cfg () =
  let open RunAsync.Syntax in
  let%bind repoPath = 
    match cfg.Config.opamRepository with
    | Config.Local local -> return local
    | Config.Remote (remote, local) ->
      let%bind () = Git.ShallowClone.update ~branch:"master" ~dst:local remote in
      return local

  and overrides = OpamOverrides.init ~cfg () in

  return {
    repoPath;
    pathsCache = OpamPathsByVersion.make ();
    overrides;
  }

let filterNone items =
  let rec aux items = function
    | [] -> items
    | None::rest -> aux items rest
    | (Some item)::rest -> aux (item::items) rest
  in
  List.rev (aux [] items)

let getVersionIndex registry ~(name : PackageName.t) =
  let f name =
    let open RunAsync.Syntax in
    let path = Path.(
      registry.repoPath
      / "packages"
      / PackageName.toString name
    ) in
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
  OpamPathsByVersion.compute registry.pathsCache name f

let getThinManifest registry ~(name : PackageName.t) ~(version : Version.t) =
  let open RunAsync.Syntax in
  let%bind index = getVersionIndex registry ~name in
  match VersionMap.find_opt version index with
  | None -> return None
  | Some packagePath ->
    let manifest =
      let path = Path.(packagePath / "opam") in
      let opamFile = OpamParser.file (Path.toString path) in
      OpamFile.parseManifest (name, version) opamFile
    in
    if not manifest.OpamFile.available
    then return None
    else
      let opamFile = Path.(packagePath / "opam") in
      let urlFile = Path.(packagePath / "url") in
      let manifest = {
        OpamFile.ThinManifest.
        name;
        opamFile;
        urlFile;
        version
      } in
    return (Some manifest)

let versions registry ~(name : PackageName.t) =
  let open RunAsync.Syntax in
  let%bind index = getVersionIndex registry ~name in
  let%bind items =
    index
    |> VersionMap.bindings
    |> List.map (fun (version, _path) -> getThinManifest registry ~name ~version)
    |> RunAsync.List.joinAll
  in
  return (
    items
    |> filterNone
    |> List.map (fun manifest -> (manifest.OpamFile.ThinManifest.version, manifest))
  )

let resolveSourceSpec srcSpec =
  let open RunAsync.Syntax in
  match srcSpec with
  | PackageInfo.SourceSpec.NoSource ->
    return PackageInfo.Source.NoSource

  | PackageInfo.SourceSpec.Archive (url, Some checksum) ->
    return (PackageInfo.Source.Archive (url, checksum))
  | PackageInfo.SourceSpec.Archive (url, None) ->
    return (PackageInfo.Source.Archive (url, "fake-checksum-fix-me"))

  | PackageInfo.SourceSpec.Git (remote, ref) ->
    let%bind commit = Git.lsRemote ?ref ~remote () in
    return (PackageInfo.Source.Git (remote, commit))

  | PackageInfo.SourceSpec.Github (user, name, ref) ->
    let remote = Printf.sprintf "https://github.com/%s/%s.git" user name in
    let%bind commit = Git.lsRemote ?ref ~remote () in
    return (PackageInfo.Source.Github (user, name, commit))

  | PackageInfo.SourceSpec.LocalPath path ->
    return (PackageInfo.Source.LocalPath path)


let version registry ~(name : PackageName.t) ~version =
  let open RunAsync.Syntax in
  match%bind getThinManifest registry ~name ~version with
  | None -> return None
  | Some { OpamFile.ThinManifest. opamFile; urlFile; name; version } ->
    let%bind sourceSpec =
      if%bind Fs.exists urlFile
      then return (OpamFile.parseUrlFile (OpamParser.file (Path.toString urlFile)))
      else return PackageInfo.SourceSpec.NoSource
    in
    let%bind source = resolveSourceSpec sourceSpec in
    let manifest =
      let manifest =
        OpamFile.parseManifest (name, version) (OpamParser.file (Path.toString opamFile))
      in
      {manifest with source}
    in
    begin match%bind OpamOverrides.get registry.overrides name version with
      | None ->
        return (Some manifest)
      | Some override ->
        let manifest = OpamOverrides.apply manifest override in
        return (Some manifest)
    end
