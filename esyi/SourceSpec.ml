open Sexplib0.Sexp_conv

type t =
  | Archive of {
      url : string;
      checksum : Checksum.t option;
    }
  | Git of {
      remote : string;
      ref : string option;
      manifest : ManifestSpec.Filename.t option;
    }
  | Github of {
      user : string;
      repo : string;
      ref : string option;
      manifest : ManifestSpec.Filename.t option;
    }
  | LocalPath of {
      path : Path.t;
      manifest : ManifestSpec.Filename.t option;
    }
  | LocalPathLink of {
      path : Path.t;
      manifest : ManifestSpec.Filename.t option;
    }
  | NoSource
  [@@deriving ord, sexp_of]

let show = function
  | Github {user; repo; ref = None; manifest = None;} ->
    Printf.sprintf "github:%s/%s" user repo
  | Github {user; repo; ref = None; manifest = Some manifest;} ->
    Printf.sprintf "github:%s/%s:%s" user repo (ManifestSpec.Filename.show manifest)
  | Github {user; repo; ref = Some ref; manifest = None} ->
    Printf.sprintf "github:%s/%s#%s" user repo ref
  | Github {user; repo; ref = Some ref; manifest = Some manifest} ->
    Printf.sprintf "github:%s/%s:%s#%s" user repo (ManifestSpec.Filename.show manifest) ref

  | Git {remote; ref = None; manifest = None;} ->
    Printf.sprintf "git:%s" remote
  | Git {remote; ref = None; manifest = Some manifest;} ->
    Printf.sprintf "git:%s:%s" remote (ManifestSpec.Filename.show manifest)
  | Git {remote; ref = Some ref; manifest = None} ->
    Printf.sprintf "git:%s#%s" remote ref
  | Git {remote; ref = Some ref; manifest = Some manifest} ->
    Printf.sprintf "git:%s:%s#%s" remote (ManifestSpec.Filename.show manifest) ref

  | Archive {url; checksum = Some checksum} ->
    Printf.sprintf "archive:%s#%s" url (Checksum.show checksum)
  | Archive {url; checksum = None} ->
    Printf.sprintf "archive:%s" url

  | LocalPath {path; manifest = None;} ->
    Printf.sprintf "path:%s" (Path.show path)
  | LocalPath {path; manifest = Some manifest;} ->
    Printf.sprintf "path:%s/%s" (Path.show path) (ManifestSpec.Filename.show manifest)

  | LocalPathLink {path; manifest = None;} ->
    Printf.sprintf "link:%s" (Path.show path)
  | LocalPathLink {path; manifest = Some manifest;} ->
    Printf.sprintf "link:%s/%s" (Path.show path) (ManifestSpec.Filename.show manifest)

  | NoSource -> "no-source:"

let to_yojson src = `String (show src)

let pp fmt spec =
  Fmt.pf fmt "%s" (show spec)

let ofSource (source : Source.t) =
  match source with
  | Source.Archive {url; checksum} -> Archive {url; checksum = Some checksum}
  | Source.Git {remote; commit; manifest;} ->
    Git {remote; ref =  Some commit; manifest;}
  | Source.Github {user; repo; commit; manifest;} ->
    Github {user; repo; ref = Some commit; manifest;}
  | Source.LocalPath {path; manifest;} ->
    LocalPath {path; manifest;}
  | Source.LocalPathLink {path; manifest;} ->
    LocalPathLink {path; manifest;}
  | Source.NoSource -> NoSource

module Parse = struct
  include Parse

  let manifestFilenameBeforeSharp =
    till (fun c -> c <> '#') ManifestSpec.Filename.parser

  let collectString xs =
    let l = List.length xs in
    let s = Bytes.create l in
    List.iteri ~f:(fun i c -> Bytes.set s i c) xs;
    Bytes.unsafe_to_string s

  let githubWithoutProto =
    let user = take_while1 (fun c -> c <> '/') in
    let repo =
      many_till any_char (string ".git") >>| collectString
      <|> take_while1 (fun c -> c <> '#' && c <> ':' && c <> '/')
    in
    let manifest = maybe (char ':' *> manifestFilenameBeforeSharp) in
    let ref = maybe (char '#' *> take_while1 (fun _ -> true)) in
    let make user repo manifest ref =
      Github { user; repo; ref; manifest; }
    in
    make <$> (user <* char '/') <*> repo <*> manifest <*> ref

  let github =
    let prefix = string "github:" <|> string "gh:" in
    prefix *> githubWithoutProto

  let git =
    let prefix = string "git+" in
    let proto =
      let gitWithProto =
        prefix *> (
          string "https:"
          <|> string "http:"
          <|> string "ssh:"
          <|> string "ftp:"
          <|> string "rsync:"
        )
      in
      gitWithProto <|> string "git:"
    in
    let remote = take_while1 (fun c -> c <> '#' && c <> ':') in
    let manifest = maybe (char ':' *> manifestFilenameBeforeSharp) in
    let ref = maybe (char '#' *> take_while1 (fun _ -> true)) in
    let make proto remote manifest ref =
      Git { remote = proto ^ remote; ref; manifest; }
    in
    (make <$> proto <*> remote <*> manifest <*> ref)

  let archive =
    let proto = string "https:" <|> string "http:" in
    let url = take_while1 (fun c -> c <> '#') in
    let checksum = maybe (char '#' *> Checksum.parser) in
    let make proto url checksum =
      Archive { url = proto ^ url; checksum; }
    in
    (make <$> proto <*> url <*> checksum)

  let pathWithoutProto make =
    let path = take_while1 (fun _ -> true) in
    let make path =
      let path = Path.(normalizeAndRemoveEmptySeg (v path)) in
      let path, manifest =
        match ManifestSpec.Filename.ofString (Path.basename path) with
        | Ok manifest ->
          let path = Path.(remEmptySeg (parent path)) in
          path, Some manifest
        | Error _ ->
          path, None
      in
      make path manifest
    in
    (make <$> path)

  let pathLike proto make =
    string proto *> pathWithoutProto make

  let file =
    let make path manifest = LocalPath { path; manifest; } in
    pathLike "file:" make

  let path =
    let make path manifest = LocalPath { path; manifest; } in
    pathLike "path:" make

  let link =
    let make path manifest = LocalPathLink { path; manifest; } in
    pathLike "link:" make

  let source =
    let source = Parse.(
      github
      <|> git
      <|> archive
      <|> file
      <|> path
      <|> link
      <|> githubWithoutProto
    ) in
    let makePath path manifest = LocalPath { path; manifest; } in
    match%bind peek_char_fail with
    | '.'
    | '/' -> pathWithoutProto makePath
    | _ -> source

end

let parser = Parse.source

let parse =
  Parse.(parse source)

module Map = Map.Make(struct
  type nonrec t = t
  let compare = compare
end)

module Set = Set.Make(struct
  type nonrec t = t
  let compare = compare
end)
