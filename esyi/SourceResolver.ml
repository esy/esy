module PackageOverride = struct
  type t = {
    source : Source.t;
    override : Package.Overrides.override;
  }

  let of_yojson json =
    let open Result.Syntax in
    let%bind source =
      Json.Decode.fieldWith
        ~name:"source"
        Source.relaxed_of_yojson
        json
    in
    let%bind override =
      Json.Decode.fieldWith
      ~name:"override"
      Package.Overrides.override_of_yojson
      json
    in
    return {source; override;}

end

type resolution = {
  overrides : Package.Overrides.t;
  source : Source.t;
  manifest : manifest option;
  paths : Path.Set.t;
}

and manifest = {
  kind : ManifestSpec.Filename.kind;
  filename : string;
  suggestedPackageName : string;
  data : string;
}

type state =
  | EmptyManifest
  | Manifest of manifest
  | Override of PackageOverride.t

let rebaseSource ~(base : Source.t) (source : Source.t) =
  let open Run.Syntax in
  match source, base with
  | LocalPathLink _, _ -> error "link is not supported at manifest overrides"
  | LocalPath info, LocalPath {path = basePath; _}
  | LocalPath info, LocalPathLink {path = basePath; _} ->
    let path = Path.(basePath // info.path |> normalizeAndRemoveEmptySeg) in
    return (Source.LocalPath {info with path;})
  | LocalPath _, _ -> failwith "TODO"
  | source, _ -> return source

let suggestPackageName ~fallback (kind, filename) =
  let ensurehasOpamScope name =
    match Astring.String.cut ~sep:"@opam/" name with
    | Some ("", _) -> name
    | Some _
    | None -> "@opam/" ^ name
  in
  let name =
    match ManifestSpec.Filename.inferPackageName (kind, filename) with
    | Some name -> name
    | None -> fallback
  in
  match kind with
  | ManifestSpec.Filename.Esy -> name
  | ManifestSpec.Filename.Opam -> ensurehasOpamScope name

let ofGithub
  ?manifest
  user
  repo
  ref =
  let open RunAsync.Syntax in
  let fetchFile name =
    let url =
      Printf.sprintf
        "https://raw.githubusercontent.com/%s/%s/%s/%s"
        user repo ref name
    in
    Curl.get url
  in

  let rec tryFilename filenames =
    match filenames with
    | [] -> return EmptyManifest
    | (kind, filename)::rest ->
      begin match%lwt fetchFile filename with
      | Error _ -> tryFilename rest
      | Ok data ->
        match kind with
        | ManifestSpec.Filename.Esy ->
          begin match Json.parseStringWith PackageOverride.of_yojson data with
          | Ok override -> return (Override override)
          | Error err ->
            let suggestedPackageName = suggestPackageName ~fallback:repo (kind, filename) in
            Logs_lwt.debug (fun m ->
              m "not an override %s/%s:%s: %a" user repo filename Run.ppError err
              );%lwt
            return (Manifest {data; filename; kind; suggestedPackageName;})
          end
        | ManifestSpec.Filename.Opam ->
          let suggestedPackageName = suggestPackageName ~fallback:repo (kind, filename) in
          return (Manifest {data; filename; kind; suggestedPackageName;})
      end
  in

  let filenames =
    match manifest with
    | Some manifest -> [manifest]
    | None -> [
      ManifestSpec.Filename.Esy, "esy.json";
      ManifestSpec.Filename.Esy, "package.json"
    ]
  in

  tryFilename filenames

let ofPath ?manifest (path : Path.t)
  =

  let open RunAsync.Syntax in

  let rec tryFilename filenames =
    match filenames with
    | [] -> return EmptyManifest
    | (kind, filename)::rest ->

      let suggestedPackageName =
        suggestPackageName
          ~fallback:(Path.(path |> normalize |> remEmptySeg |> basename))
          (kind, filename)
      in

      let path = Path.(path / filename) in
      if%bind Fs.exists path
      then
        let%bind data = Fs.readFile path in
        match kind with
        | ManifestSpec.Filename.Esy ->
          begin match Json.parseStringWith PackageOverride.of_yojson data with
          | Ok override -> return (Override override)
          | Error err ->
            Logs_lwt.debug (fun m ->
              m "not an override %a: %a" Path.pp path Run.ppError err
              );%lwt
            return (Manifest {data; filename; kind; suggestedPackageName;})
          end
        | ManifestSpec.Filename.Opam ->
            return (Manifest {data; filename; kind; suggestedPackageName;})
      else
        tryFilename rest
  in
  let%bind filenames =
    match manifest with
    | Some manifest ->
      ManifestSpec.findManifestsAtPath path manifest
    | None ->
      return [
        ManifestSpec.Filename.Esy, "esy.json";
        ManifestSpec.Filename.Esy, "package.json";
        ManifestSpec.Filename.Opam, "opam";
        ManifestSpec.Filename.Opam, (Path.basename path ^ ".opam");
      ]
  in
  tryFilename filenames

let resolve
  ?(overrides=Package.Overrides.empty)
  ~cfg
  ~root
  (source : Source.t) =
  let open RunAsync.Syntax in

  let resolve' (source : Source.t) =
    Logs_lwt.debug (fun m -> m "fetching metadata %a" Source.pp source);%lwt
    match source with
    | LocalPath {path; manifest}
    | LocalPathLink {path; manifest} ->
      let%bind pkg = ofPath ?manifest Path.(root // path) in
      return (pkg, Some path)
    | Git {remote; commit; manifest;} ->
      let manifest = Option.map ~f:(fun m -> ManifestSpec.One m) manifest in
      Fs.withTempDir begin fun repo ->
        let%bind () = Git.clone ~dst:repo ~remote () in
        let%bind () = Git.checkout ~ref:commit ~repo () in
        let%bind pkg = ofPath ?manifest repo in
        return (pkg, None)
      end
    | Github {user; repo; commit; manifest;} ->
      let%bind pkg = ofGithub ?manifest user repo commit in
      return (pkg, None)
    | Archive _ ->
      Fs.withTempDir begin fun path ->
        let%bind () =
          SourceStorage.fetchAndUnpack
            ~cfg
            ~dst:path
            source
        in
        let%bind pkg = ofPath path in
      return (pkg, None)
      end

    | NoSource ->
      return (EmptyManifest, None)
  in

  let maybeAddToPathSet path paths =
    match path with
    | Some path -> Path.Set.add path paths
    | None -> paths
  in

  let rec loop' ~overrides ~paths source =
    match%bind resolve' source with
    | EmptyManifest, path ->
      return {
        manifest = None;
        overrides;
        source;
        paths = maybeAddToPathSet path Path.Set.empty;
      }
    | Manifest manifest, path ->
      return {
        manifest = Some manifest;
        overrides;
        source;
        paths = maybeAddToPathSet path Path.Set.empty;
      }
    | Override {source = nextSource; override}, path ->
      let%bind nextSource = RunAsync.ofRun (rebaseSource ~base:source nextSource) in
      Logs_lwt.debug (fun m -> m "override: %a -> %a@." Source.pp source Source.pp nextSource);%lwt
      let overrides = Package.Overrides.add override overrides in
      let paths = maybeAddToPathSet path paths in
      loop' ~overrides ~paths nextSource
  in

  loop' ~overrides ~paths:Path.Set.empty source
