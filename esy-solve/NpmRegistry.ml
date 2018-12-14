module Packument = struct
  type t = {
    versions : Json.t StringMap.t;
    distTags : EsyInstall.SemverVersion.Version.t StringMap.t [@key "dist-tags"];
  } [@@deriving of_yojson { strict = false }]
end

type versions = {
  versions : EsyInstall.SemverVersion.Version.t list;
  distTags : EsyInstall.SemverVersion.Version.t StringMap.t;
}

module VersionsCache = Memoize.Make(struct
  type key = string
  type value = versions option RunAsync.t
end)

module PackageCache = Memoize.Make(struct
  type key = string * EsyInstall.SemverVersion.Version.t
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

let versions ?(fullMetadata=false) ~name registry () =
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
          let%bind version = EsyInstall.SemverVersion.Version.parse version in
          PackageCache.ensureComputed registry.pkgCache (name, version) begin fun () ->
            let version = EsyInstall.Version.Npm version in
            RunAsync.ofRun (PackageJson.packageOfJson ~name ~version packageJson)
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
  let%bind _: versions option = versions ~fullMetadata:true ~name registry () in
  match PackageCache.get registry.pkgCache (name, version) with
  | None -> errorf "no package found on npm %s@%a" name EsyInstall.SemverVersion.Version.pp version
  | Some pkg -> pkg
