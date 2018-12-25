module BuildType = struct
  include BuildType
  include BuildType.AsInPackageJson
end

module InstallManifestV1 = struct
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
      resolutions : (Resolutions.t [@default Resolutions.empty]);
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

    let dependencies =
      let f req = req.Req.name <> "esy" in
      List.filter ~f dependencies
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
      | false -> return Resolutions.empty
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
      InstallManifest.
      name;
      version;
      originalVersion;
      originalName = pkgJson.name;
      overrides = Overrides.empty;
      dependencies = InstallManifest.Dependencies.NpmFormula dependencies;
      devDependencies = InstallManifest.Dependencies.NpmFormula devDependencies;
      peerDependencies = pkgJson.peerDependencies;
      optDependencies = pkgJson.optDependencies |> StringMap.keys |> StringSet.of_list;
      resolutions;
      source;
      kind = if Option.isSome pkgJson.esy then Esy else Npm;
    }
end

module BuildManifestV1 = struct
  type packageJson = {
    name: string option [@default None];
    version: Version.t option [@default None];
    esy: packageJsonEsy option [@default None];
  } [@@deriving (of_yojson {strict = false})]

  and packageJsonEsy = {
    build: (CommandList.t [@default CommandList.empty]);
    buildDev: (CommandList.t option [@default None]);
    install: (CommandList.t [@default CommandList.empty]);
    buildsInSource: (BuildType.t [@default BuildType.OutOfSource]);
    exportedEnv: (ExportedEnv.t [@default ExportedEnv.empty]);
    buildEnv: (BuildEnv.t [@default BuildEnv.empty]);
    sandboxEnv: (SandboxEnv.t [@default SandboxEnv.empty]);
  } [@@deriving (of_yojson { strict = false })]

  let ofJson json =
    let open Run.Syntax in
    let%bind pkgJson = Json.parseJsonWith packageJson_of_yojson json in
    match pkgJson.esy with
    | Some m ->
      let build = {
        BuildManifest.
        name = pkgJson.name;
        version = pkgJson.version;
        buildType = m.buildsInSource;
        exportedEnv = m.exportedEnv;
        buildEnv = m.buildEnv;
        build = EsyCommands (m.build);
        buildDev = m.buildDev;
        install = EsyCommands (m.install);
        patches = [];
        substs = [];
      } in
      return (Some build)
    | None -> return None
end

module EsyVersion = struct
  type t = int

  let default = 1
  let supported = [default;]

  let pp fmt version =
    Fmt.pf fmt "%i.0.0" version

  let of_yojson json =
    let open Result.Syntax in
    let%bind constr = Json.Decode.string json in
    let%bind constr = SemverVersion.Formula.parse constr in
    match constr with
    | [[
        SemverVersion.Constraint.EQ {
          SemverVersion.Version.
          major = v;
          minor = 0;
          patch = 0;
          prerelease = [];
          build = []
        }
      ]] -> return v
    | invalid ->
      errorf {|invalid "esy" version: %a must be one of: %a|}
        SemverVersion.Formula.DNF.pp invalid
        Fmt.(list pp) supported

  module OfPackageJson = struct
    type dependencies = {
      esy : t [@default default]
    }

    let dependencies_of_yojson json =
      let open Result.Syntax in
      match json with
      | `Assoc items ->
        let f (key, _json) = key = "esy" in
        begin match List.find_opt ~f items with
        | Some (_, json) ->
          let%bind esy = of_yojson json in
          return {esy;}
        | None -> return {esy = default;}
        end
      | _ -> errorf {|reading "dependencies": expected an object|}

    type manifest = {
      dependencies : dependencies [@default {esy = default;}]
    } [@@deriving of_yojson { strict = false; }]

    let parse json =
      match Json.parseJsonWith manifest_of_yojson json with
      | Ok manifest -> Ok manifest.dependencies.esy
      | Error err -> Error err
  end
end

let unknownEsyVersionError version =
  Run.errorf
    {|unsupported "esy" version: %a must be one of: %a|}
    EsyVersion.pp version
    Fmt.(list EsyVersion.pp) EsyVersion.supported

let installManifest
  ?(parseResolutions=false)
  ?(parseDevDependencies=false)
  ?source
  ~name
  ~version
  json =
  let open Run.Syntax in
  let%bind esyVersion = EsyVersion.OfPackageJson.parse json in
  match esyVersion with
  | 1 -> InstallManifestV1.ofJson ~parseResolutions ~parseDevDependencies ?source ~name ~version json
  | v -> unknownEsyVersionError v

let buildManifest json =
  let open Run.Syntax in
  let%bind esyVersion = EsyVersion.OfPackageJson.parse json in
  match esyVersion with
  | 1 -> BuildManifestV1.ofJson json
  | v -> unknownEsyVersionError v
