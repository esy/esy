module Version = PackageInfo.Version
module Source = PackageInfo.Source

type t = {
  name : string;
  version : PackageInfo.Version.t;
  source : PackageInfo.Source.t;
  dependencies: PackageInfo.DependenciesInfo.t;
  opam : PackageInfo.OpamInfo.t option;
}

and manifest =
  | Opam of OpamFile.manifest
  | PackageJson of PackageJson.t

let make ~version manifest =
  let open Run.Syntax in
  let dependencies =
    match manifest with
    | Opam manifest -> OpamFile.dependencies manifest
    | PackageJson manifest -> PackageJson.dependencies manifest
  in
  let%bind source =
    match version with
    | Version.Source (Source.Github (user, name, ref)) ->
      Run.return (PackageInfo.Source.Github (user, name, ref))
    | Version.Source (Source.LocalPath path)  ->
      Run.return (PackageInfo.Source.LocalPath path)
    | _ -> begin
      match manifest with
      | Opam manifest -> return (OpamFile.source manifest)
      | PackageJson json -> PackageJson.source json
    end
  in
  let name =
    match manifest with
    | Opam manifest -> OpamFile.name manifest
    | PackageJson manifest  -> PackageJson.name manifest
  in
  let opam =
    match manifest with
    | Opam manifest ->
      Some (OpamFile.toPackageJson manifest version)
    | PackageJson _ -> None
  in
  return {
    name;
    version;
    dependencies;
    source;
    opam;
  }

module Github = struct
  let getManifest user repo ref =
    let open RunAsync.Syntax in
    let fetchFile name =
      let url =
        "https://raw.githubusercontent.com"
        ^ "/" ^ user
        ^ "/" ^ repo
        ^ "/" ^ Option.orDefault ~default:"master" ref
        ^ "/" ^ name
      in
      Curl.get url
    in
    match%lwt fetchFile "esy.json" with
    | Ok data ->
      let%bind packageJson =
        RunAsync.ofRun (Json.parseStringWith PackageJson.of_yojson data)
      in
      return (PackageJson packageJson)
    | Error _ ->
      begin match%lwt fetchFile "package.json" with
      | Ok text ->
        let%bind packageJson =
          RunAsync.ofRun (Json.parseStringWith PackageJson.of_yojson text)
        in
        return (PackageJson packageJson)
      | Error _ ->
        error "no manifest found"
      end
end
