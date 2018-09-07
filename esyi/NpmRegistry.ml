module Esy = PackageJson.EsyPackageJson

module PackageJson = struct
  type t = {
    name : string;
    version : string;
    dependencies : (Package.NpmDependencies.t [@default Package.NpmDependencies.empty]);
    devDependencies : (Package.NpmDependencies.t [@default Package.NpmDependencies.empty]);
    dist : dist;
    esy : (PackageJson.EsyPackageJson.t option [@default None]);
  } [@@deriving of_yojson { strict = false }]

  and dist = {
    tarball : string;
    shasum : string;
  }
end

module Packument = struct
  type t = {
    versions : PackageJson.t StringMap.t;
    distTags : SemverVersion.Version.t StringMap.t [@key "dist-tags"];
  } [@@deriving of_yojson { strict = false }]
end

let packageJsonToPackage ?name ?version (pkgJson : PackageJson.t) =
  let open Run.Syntax in
  let name =
    match name with
    | Some name -> name
    | None -> pkgJson.name
  in
  let%bind originalVersion = Run.ofStringError (
    let open Result.Syntax in
    let%bind version = SemverVersion.Version.parse pkgJson.version in
    return (Version.Npm version)
  ) in
  let version =
    match version with
    | Some version -> Version.Npm version
    | None -> originalVersion
  in
  let source =
    match version with
    | Version.Source src -> src
    | _ ->
      Source.Archive {
        url = pkgJson.dist.tarball;
        checksum = Checksum.Sha1, pkgJson.dist.shasum;
      }
  in

  let dependencies =
    match pkgJson.esy with
    | None
    | Some {Esy. _dependenciesForNewEsyInstaller= None} ->
      pkgJson.dependencies
    | Some {Esy. _dependenciesForNewEsyInstaller= Some dependencies} ->
      dependencies
  in

  let pkg = {
    Package.
    name;
    version;
    originalVersion = Some originalVersion;
    dependencies = Package.Dependencies.NpmFormula dependencies;
    devDependencies = Package.Dependencies.NpmFormula pkgJson.devDependencies;
    source = Package.Source source, [];
    opam = None;
    kind =
      (match pkgJson.esy with
        | Some _ -> Esy
        | None -> Npm);
  } in

  return pkg


type versions = {
  versions : SemverVersion.Version.t list;
  distTags : SemverVersion.Version.t StringMap.t;
}

module VersionsCache = Memoize.Make(struct
  type key = string
  type value = versions option RunAsync.t
end)

module PackageCache = Memoize.Make(struct
  type key = string * SemverVersion.Version.t
  type value = Package.t RunAsync.t
end)

type t = {
  url : string;
  versionsCache : VersionsCache.t;
  pkgCache : PackageCache.t;
  queue : LwtTaskQueue.t;
}

let rec retryInCaseOfError ~num ~desc  f =
  match%lwt f () with
  | Ok resp -> RunAsync.return resp
  | Error _ when num > 0 ->
    let%lwt () =
      Logs_lwt.warn (fun m -> m "failed to %s, retrying (attempts left: %i)" desc num)
    in
    retryInCaseOfError ~num:(num - 1) ~desc f
  | Error err -> Lwt.return (Error err)

let make ?(concurrency=40) ?url () =
  let url =
    match url with
    | None -> "http://registry.npmjs.org/"
    | Some url -> url
  in
  {
    url;
    versionsCache = VersionsCache.make ();
    pkgCache = PackageCache.make ();
    queue = LwtTaskQueue.create ~concurrency ();
  }

let versions ?(fullMetadata= false) ~name registry () =
  let open RunAsync.Syntax in
  let fetchVersions () =
    let fetch =
      let name = Str.global_replace (Str.regexp "/") "%2f" name in
      let desc = Format.asprintf "fetch %s" name in
      let accept =
        if fullMetadata
        then None
        else Some "application/vnd.npm.install-v1+json"
      in
      retryInCaseOfError ~num:3 ~desc
        (fun () -> Curl.getOrNotFound ?accept (registry.url ^ "/" ^ name))
    in
    match%bind fetch with
    | Curl.NotFound -> return None
    | Curl.Success data ->
      let%bind packument =
        RunAsync.context (
        Json.parseStringWith Packument.of_yojson data
        |> RunAsync.ofRun
        ) "parsing packument"
      in
      let%bind versions = RunAsync.ofStringError (
        let f (version, packageJson) =
          let open Result.Syntax in
          let%bind version = SemverVersion.Version.parse version in
          PackageCache.ensureComputed registry.pkgCache (name, version) begin fun () ->
            RunAsync.ofRun (packageJsonToPackage ~version packageJson)
          end;
          return version
        in
        packument.Packument.versions
        |> StringMap.bindings
        |> Result.List.map ~f
      ) in
      return (Some {versions; distTags = packument.Packument.distTags;})
  in
  fetchVersions
  |> LwtTaskQueue.queued registry.queue
  |> VersionsCache.compute registry.versionsCache name

let package ~name ~version registry () =
  let open RunAsync.Syntax in
  let fetchPackage () =
    let desc = Format.asprintf "fetch %s@%a" name SemverVersion.Version.pp version in
    let name = Str.global_replace (Str.regexp "/") "%2f" name in
    let%bind data =
      let url = registry.url ^ "/" ^ name ^ "/" ^ SemverVersion.Version.toString version in
      retryInCaseOfError ~num:3 ~desc (fun () -> Curl.get url)
    in
    RunAsync.ofRun (
      let open Run.Syntax in
      let%bind pkgJson = Json.parseStringWith PackageJson.of_yojson data in
      let%bind pkg = packageJsonToPackage pkgJson in
      return pkg
    )
  in
  fetchPackage
  |> LwtTaskQueue.queued registry.queue
  |> PackageCache.compute registry.pkgCache (name, version)
