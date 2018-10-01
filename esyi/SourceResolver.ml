module PackageOverride = struct
  type t = {
    source : Source.t;
    override : Package.Overrides.override;
  } [@@deriving of_yojson]

end

type resolution = {
  overrides : Package.Overrides.t;
  source : Source.t;
  manifest : manifest option;
}

and manifest = {
  kind : ManifestSpec.Filename.kind;
  filename : string;
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
    | (kind, fname)::rest ->
      begin match%lwt fetchFile fname with
      | Error _ -> tryFilename rest
      | Ok data -> return (Manifest {filename = fname; data = data; kind = kind;})
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
    | (kind, fname)::rest ->
      let path = Path.(path / fname) in
      if%bind Fs.exists path
      then
        let%bind data = Fs.readFile path in
        match kind with
        | ManifestSpec.Filename.Esy ->
          begin match Json.parseStringWith PackageOverride.of_yojson data with
          | Ok override -> return (Override override)
          | Error _ -> return (Manifest {data; filename = fname; kind})
          end
        | ManifestSpec.Filename.Opam ->
          return (Manifest {data; filename = fname; kind})
      else
        tryFilename rest
  in
  let filenames =
    match manifest with
    | Some manifest -> [manifest]
    | None -> [
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
      return pkg
    | Git {remote; commit; manifest;} ->
      Fs.withTempDir begin fun repo ->
        let%bind () = Git.clone ~dst:repo ~remote () in
        let%bind () = Git.checkout ~ref:commit ~repo () in
        ofPath ?manifest repo
      end
    | Github {user; repo; commit; manifest;} ->
      ofGithub ?manifest user repo commit
    | Archive _ ->
      Fs.withTempDir begin fun path ->
        let%bind () =
          SourceStorage.fetchAndUnpack
            ~cfg
            ~dst:path
            source
        in
        ofPath path
      end

    | NoSource ->
      return EmptyManifest
  in

  let rec loop' ~overrides source =
    match%bind resolve' source with
    | EmptyManifest ->
      return {manifest = None; overrides; source;}
    | Manifest manifest ->
      return {manifest = Some manifest; overrides; source;}
    | Override {source = nextSource; override} ->
      let%bind nextSource = RunAsync.ofRun (rebaseSource ~base:source nextSource) in
      Logs_lwt.debug (fun m -> m "override: %a -> %a@." Source.pp source Source.pp nextSource);%lwt
      let overrides = Package.Overrides.add override overrides in
      loop' ~overrides nextSource
  in

  loop' ~overrides source
