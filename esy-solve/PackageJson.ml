open EsyPackageConfig

module NpmFormula = PackageConfig.NpmFormula

module V1 = struct
  module EsyPackageJson = struct
    type t = {
      _dependenciesForNewEsyInstaller : NpmFormula.t option [@default None];
    } [@@deriving of_yojson { strict = false }]
  end

  module Manifest = struct
    type t = {
      name : string option [@default None];
      version : SemverVersion.Version.t option [@default None];
      dependencies : NpmFormula.t [@default NpmFormula.empty];
      peerDependencies : NpmFormula.t [@default NpmFormula.empty];
      optDependencies : Json.t StringMap.t [@default StringMap.empty];
      esy : EsyPackageJson.t option [@default None];
      dist : dist option [@default None]
    } [@@deriving of_yojson { strict = false }]

    and dist = {
      tarball : string;
      shasum : string;
    }

  end

  module ResolutionsOfManifest = struct
    type t = {
      resolutions : (PackageConfig.Resolutions.t [@default PackageConfig.Resolutions.empty]);
    } [@@deriving of_yojson { strict = false }]
  end

  module DevDependenciesOfManifest = struct
    type t = {
      devDependencies : NpmFormula.t [@default NpmFormula.empty];
    } [@@deriving of_yojson { strict = false }]
  end

  let rebaseDependencies source reqs =
    let open Run.Syntax in
    let f req =
      match source, req.Req.spec with
      | (Source.Dist LocalPath {path = basePath; _}
        | Source.Link {path = basePath; _}),
        VersionSpec.Source (SourceSpec.LocalPath {path; manifest;}) ->
        let path = DistPath.rebase ~base:basePath path in
        let spec = VersionSpec.Source (SourceSpec.LocalPath {path; manifest;}) in
        return (Req.make ~name:req.name ~spec)
      | _, VersionSpec.Source (SourceSpec.LocalPath _) ->
        errorf
          "path constraints %a are not allowed from %a"
          VersionSpec.pp req.spec Source.pp source
      | _ -> return req
    in
    Result.List.map ~f reqs

  let ofJson
    ~parseResolutions
    ~parseDevDependencies
    ?source
    ~name
    ~version
    json =
    let open Run.Syntax in
    let%bind pkgJson = Json.parseJsonWith Manifest.of_yojson json in
    let originalVersion =
      match pkgJson.Manifest.version with
      | Some version -> Some (Version.Npm version)
      | None -> None
    in

    let%bind source =
      match source, pkgJson.dist with
      | Some source, _ -> return source
      | None, Some dist ->
        return (Source.Dist (Archive {
          url = dist.tarball;
          checksum = Checksum.Sha1, dist.shasum;
        }))
      | None, None ->
        error "unable to determine package source, missing 'dist' metadata"
    in

    let dependencies =
      match pkgJson.esy with
      | None
      | Some {EsyPackageJson. _dependenciesForNewEsyInstaller= None} ->
        pkgJson.dependencies
      | Some {EsyPackageJson. _dependenciesForNewEsyInstaller= Some dependencies} ->
        dependencies
    in

    let%bind dependencies = rebaseDependencies source dependencies in

    let%bind devDependencies =
      match parseDevDependencies with
      | false -> return NpmFormula.empty
      | true ->
        let%bind {DevDependenciesOfManifest. devDependencies} =
          Json.parseJsonWith DevDependenciesOfManifest.of_yojson json
        in
        let%bind devDependencies = rebaseDependencies source devDependencies in
        return devDependencies
    in

    let%bind resolutions =
      match parseResolutions with
      | false -> return PackageConfig.Resolutions.empty
      | true ->
        let%bind {ResolutionsOfManifest. resolutions} =
          Json.parseJsonWith ResolutionsOfManifest.of_yojson json
        in
        return resolutions
    in

    let source =
      match source with
      | Source.Link {path; manifest;} ->
        PackageSource.Link {path; manifest;}
      | Source.Dist dist ->
        PackageSource.Install {source = dist, []; opam = None;}
    in

    return {
      Package.
      name;
      version;
      originalVersion;
      originalName = pkgJson.name;
      overrides = Overrides.empty;
      dependencies = Package.Dependencies.NpmFormula dependencies;
      devDependencies = Package.Dependencies.NpmFormula devDependencies;
      peerDependencies = pkgJson.peerDependencies;
      optDependencies = pkgJson.optDependencies |> StringMap.keys |> StringSet.of_list;
      resolutions;
      source;
      kind = if Option.isSome pkgJson.esy then Esy else Npm;
    }
end

module EsyVersion = struct
  let default = "1.0.0"
  let supported = [default;]

  type t =
    {dependencies : dependencies [@default {esy = default;}]}
    [@@deriving of_yojson]
  and dependencies =
    {esy : string [@default default]}

  let ofJson json =
    match Json.parseJsonWith of_yojson json with
    | Ok manifest -> manifest.dependencies.esy
    | Error _ -> default
end

let ofJson
  ?(parseResolutions=false)
  ?(parseDevDependencies=false)
  ?source
  ~name
  ~version
  json =
  match EsyVersion.ofJson json with
  | "1.0.0" -> V1.ofJson ~parseResolutions ~parseDevDependencies ?source ~name ~version json
  | unknownVersion ->
    Run.errorf
      "unsupported esy version declaration found: %s must be one of %a"
      unknownVersion Fmt.(list string) EsyVersion.supported
