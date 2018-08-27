module Version = SemverVersion.Version

module Packument = struct
  module Versions = struct
    type t = Manifest.PackageJson.t StringMap.t
    let of_yojson : t Json.decoder = Json.Parse.stringMap Manifest.PackageJson.of_yojson
  end

  type t = {
    versions: Versions.t;
  } [@@deriving of_yojson { strict = false }]
end

let rec retryInCaseOfError ~num ~desc  f =
  match%lwt f () with
  | Ok resp -> RunAsync.return resp
  | Error _ when num > 0 ->
    let%lwt () =
      Logs_lwt.warn (fun m -> m "failed to %s, retrying (attempts left: %i)" desc num)
    in
    retryInCaseOfError ~num:(num - 1) ~desc f
  | Error err -> Lwt.return (Error err)

let versions ?(fullMetadata= false) ~cfg ~name () =
  let open RunAsync.Syntax in
  let fetch =
    let name = Str.global_replace (Str.regexp "/") "%2f" name in
    let desc = Format.asprintf "fetch %s" name in
    let accept =
      if fullMetadata
      then None
      else Some "application/vnd.npm.install-v1+json"
    in
    retryInCaseOfError ~num:3 ~desc
      (fun () -> Curl.getOrNotFound ?accept (cfg.Config.npmRegistry ^ "/" ^ name))
  in
  match%bind fetch with
  | Curl.NotFound -> return []
  | Curl.Success data ->
    let%bind packument = RunAsync.ofRun (Json.parseStringWith Packument.of_yojson data) in
    let results =
      packument.Packument.versions
      |> StringMap.bindings
      |> Result.List.map
          ~f:(fun (version, packageJson) ->
              let open Result.Syntax in
              let manifest = Manifest.ofPackageJson packageJson in
              let%bind version = SemverVersion.Version.parse version in
                  return (version, manifest)
          )
    in
    RunAsync.ofStringError results

let version ~cfg ~name ~version () =
  let open RunAsync.Syntax in
  let desc = Format.asprintf "fetch %s@%a" name Version.pp version in
  let name = Str.global_replace (Str.regexp "/") "%2f" name in
  let%bind data =
    let url = cfg.Config.npmRegistry ^ "/" ^ name ^ "/" ^ Version.toString version in
    retryInCaseOfError ~num:3 ~desc (fun () -> Curl.get url)
  in
  let%bind packageJson = RunAsync.ofRun (
    Json.parseStringWith Manifest.PackageJson.of_yojson data
  ) in
  let manifest = Manifest.ofPackageJson packageJson in
  return manifest
