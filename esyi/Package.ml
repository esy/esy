type t = {
  name : string;
  version : Solution.Version.t;
  source : Types.PendingSource.t;
  dependencies: PackageJson.DependenciesInfo.t;
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
    | Solution.Version.Github (user, repo, ref) ->
      Run.return (Types.PendingSource.GithubSource (user, repo, ref))
    | Solution.Version.LocalPath path  ->
      Run.return (Types.PendingSource.File (Path.toString path))
    | _ -> begin
      match manifest with
      | Opam manifest ->
        Run.return(
          Types.PendingSource.WithOpamFile (
            OpamFile.source manifest,
            OpamFile.toPackageJson manifest version
          )
        )
      | PackageJson json -> PackageJson.source json
    end
  in
  let name =
    match manifest with
    | Opam manifest -> OpamFile.name manifest
    | PackageJson manifest  -> PackageJson.name manifest
  in
  return {
    name;
    version;
    dependencies;
    source;
  }

module Github = struct
  let getManifest user repo ref =
    let open RunAsync.Syntax in
    let fetchFile name =
      let url =
        "https://raw.githubusercontent.com/"
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
