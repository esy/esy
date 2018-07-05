module PackageName = OpamManifest.PackageName
module Source = Package.Source
module SourceSpec = Package.SourceSpec
module Version = OpamVersion.Version
module VersionMap = Map.Make(Version)
module String = Astring.String

module OpamPathsByVersion = Memoize.Make(struct
  type key = OpamManifest.PackageName.t
  type value = Path.t VersionMap.t RunAsync.t
end)


type t = {
  repoPath : Path.t;
  overrides : OpamOverrides.t;
  pathsCache : OpamPathsByVersion.t;
}

type resolution = {
  name: PackageName.t;
  version: Version.t;
  opam: Path.t;
  url: Path.t;
}

module Manifest = struct
  type t = {
    name: PackageName.t;
    version: Version.t;
    opam: OpamFile.OPAM.t;
    url: OpamFile.URL.t option;
  }

  let ofFile ~name ~version ?url opam =
    let open RunAsync.Syntax in
    let%bind opam =
      let%bind data = Fs.readFile opam in
      return (OpamFile.OPAM.read_from_string data)
    in
    let%bind url =
      match url with
      | Some url ->
        let%bind data = Fs.readFile url in
        return (Some (OpamFile.URL.read_from_string data))
      | None -> return None
    in
    return {name; version; opam; url;}
end

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
    return (List.fold_left ~init:VersionMap.empty ~f entries)
  in
  OpamPathsByVersion.compute registry.pathsCache name f

let getPackage registry ~(name : PackageName.t) ~(version : Version.t) =
  let open RunAsync.Syntax in
  let%bind index = getVersionIndex registry ~name in
  match VersionMap.find_opt version index with
  | None -> return None
  | Some packagePath ->
    let%bind manifest =
      OpamManifest.runParsePath
        ~parser:(OpamManifest.parseManifest ~name ~version)
        Path.(packagePath / "opam")
    in
    match manifest.OpamManifest.available with
    | `Ok ->
      let opam = Path.(packagePath / "opam") in
      let url = Path.(packagePath / "url") in
      let manifest = {
        name;
        opam;
        url;
        version
      } in
      return (Some manifest)
    | `IsNotAvailable ->
      return None

let versions registry ~(name : PackageName.t) =
  let open RunAsync.Syntax in
  let%bind index = getVersionIndex registry ~name in
  let%bind items =
    index
    |> VersionMap.bindings
    |> List.map ~f:(fun (version, _path) -> getPackage registry ~name ~version)
    |> RunAsync.List.joinAll
  in
  return (List.filterNone items)

let resolveSourceSpec spec =
  let open RunAsync.Syntax in

  let errorResolvingSpec spec =
      let msg =
        Format.asprintf
          "unable to resolve: %a"
          SourceSpec.pp spec
      in
      error msg
  in

  match spec with
  | SourceSpec.NoSource ->
    return Source.NoSource

  | SourceSpec.Archive (url, Some checksum) ->
    return (Source.Archive (url, checksum))
  | SourceSpec.Archive (url, None) ->
    return (Source.Archive (url, "fake-checksum-fix-me"))

  | SourceSpec.Git {remote; ref = Some ref} -> begin
    match%bind Git.lsRemote ~ref ~remote () with
    | Some commit -> return (Source.Git {remote; commit})
    | None when Git.isCommitLike ref -> return (Source.Git {remote; commit = ref})
    | None -> errorResolvingSpec spec
    end
  | SourceSpec.Git {remote; ref = None} -> begin
    match%bind Git.lsRemote ~remote () with
    | Some commit -> return (Source.Git {remote; commit})
    | None -> errorResolvingSpec spec
    end

  | SourceSpec.Github {user; repo; ref = Some ref} -> begin
    let remote = Printf.sprintf "https://github.com/%s/%s.git" user repo in
    match%bind Git.lsRemote ~ref ~remote () with
    | Some commit -> return (Source.Github {user; repo; commit})
    | None when Git.isCommitLike ref -> return (Source.Github {user; repo; commit = ref})
    | None -> errorResolvingSpec spec
    end
  | SourceSpec.Github {user; repo; ref = None} -> begin
    let remote = Printf.sprintf "https://github.com/%s/%s.git" user repo in
    match%bind Git.lsRemote ~remote () with
    | Some commit -> return (Source.Github {user; repo; commit})
    | None -> errorResolvingSpec spec
    end

  | SourceSpec.LocalPath path ->
    return (Source.LocalPath path)

  | SourceSpec.LocalPathLink path ->
    return (Source.LocalPathLink path)


let version registry ~(name : PackageName.t) ~version =
  let open RunAsync.Syntax in
  match%bind getPackage registry ~name ~version with
  | None -> return None
  | Some { opam; url; name; version } ->
    let%bind pkg = Manifest.ofFile ~name ~version ~url opam
    (* TODO: apply overrides *)
    (* begin match%bind OpamOverrides.get registry.overrides name version with *)
    (*   | None -> *)
    (*     return (Some manifest) *)
    (*   | Some override -> *)
    (*     let manifest = OpamOverrides.apply manifest override in *)
    (*     return (Some manifest) *)
    (* end *)
    in
    return (Some pkg)
