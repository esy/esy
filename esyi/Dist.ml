open Sexplib0.Sexp_conv

type t =
  | Archive of {
      url : string;
      checksum : Checksum.t;
    }
  | Git of {
      remote : string;
      commit : string;
      manifest : ManifestSpec.Filename.t option;
    }
  | Github of {
      user : string;
      repo : string;
      commit : string;
      manifest : ManifestSpec.Filename.t option;
    }
  | LocalPath of {
      path : DistPath.t;
      manifest : ManifestSpec.t option;
    }
  | NoSource
  [@@deriving ord, sexp_of]

let manifest (dist : t) =
  match dist with
  | Git { manifest = Some manifest; _ } -> Some (ManifestSpec.One manifest)
  | Git _ -> None
  | Github { manifest = Some manifest; _ } -> Some (ManifestSpec.One manifest)
  | Github _ -> None
  | LocalPath info -> info.manifest
  | Archive _ -> None
  | NoSource -> None

let show' ~showPath = function
  | Github {user; repo; commit; manifest = None;} ->
    Printf.sprintf "github:%s/%s#%s" user repo commit
  | Github {user; repo; commit; manifest = Some manifest;} ->
    Printf.sprintf "github:%s/%s:%s#%s" user repo (ManifestSpec.Filename.show manifest) commit
  | Git {remote; commit; manifest = None;} ->
    Printf.sprintf "git:%s#%s" remote commit
  | Git {remote; commit; manifest = Some manifest;} ->
    Printf.sprintf "git:%s:%s#%s" remote (ManifestSpec.Filename.show manifest) commit
  | Archive {url; checksum} ->
    Printf.sprintf "archive:%s#%s" url (Checksum.show checksum)
  | LocalPath {path; manifest = None;} ->
    Printf.sprintf "path:%s" (showPath path)
  | LocalPath {path; manifest = Some manifest;} ->
    Printf.sprintf "path:%s/%s" (showPath path) (ManifestSpec.show manifest)
  | NoSource -> "no-source:"

let show = show' ~showPath:DistPath.show
let showPretty = show' ~showPath:DistPath.showPretty

let pp fmt src =
  Fmt.pf fmt "%s" (show src)

let ppPretty fmt src =
  Fmt.pf fmt "%s" (showPretty src)

module Map = Map.Make(struct
  type nonrec t = t
  let compare = compare
end)

module Set = Set.Make(struct
  type nonrec t = t
  let compare = compare
end)

module Parse = struct
  include Parse

  let manifestFilenameBeforeSharp =
    till (fun c -> c <> '#') ManifestSpec.Filename.parser

  let withPrefix prefix p =
    string prefix *> p

  let github =
    let user = take_while1 (fun c -> c <> '/') <?> "user" in
    let repo = take_while1 (fun c -> c <> '#' && c <> ':') <?> "repo" in
    let commit = (char '#' *> take_while1 (fun _ -> true)) <|> fail "missing commit" in
    let manifest = maybe (char ':' *> manifestFilenameBeforeSharp) in
    let make user repo manifest commit =
      Github { user; repo; commit; manifest; }
    in
    make <$> (user <* char '/') <*> repo <*> manifest <*> commit

  let git =
    let proto = take_while1 (fun c -> c <> ':') in
    let remote = take_while1 (fun c -> c <> '#' && c <> ':') in
    let commit = char '#' *> take_while1 (fun c -> c <> '&') <|> fail "missing commit" in
    let manifest = maybe (char ':' *> manifestFilenameBeforeSharp) in
    let make proto remote manifest commit =
      Git { remote = proto ^ ":" ^ remote; commit; manifest; }
    in
    make <$> proto <* char ':' <*> remote <*> manifest <*> commit

  let archive =
    let proto = string "http://" <|> string "https://" in
    let host = take_while1 (fun c -> c <> '#') in
    let make proto host checksum =
      Archive { url = proto ^ host; checksum; }
    in
    (lift3 make) proto (host <* char '#') Checksum.parser

  let pathLike ~requirePathSep make =
    let make path =
      let path = Path.(normalizeAndRemoveEmptySeg (v path)) in
      let path, manifest =
        match ManifestSpec.ofString (Path.basename path) with
        | Ok manifest ->
          let path = Path.(remEmptySeg (parent path)) in
          path, Some manifest
        | Error _ ->
          path, None
      in
      make (DistPath.ofPath path) manifest
    in

    let path =
      scan
        false
        (fun seenPathSep c -> Some (seenPathSep || c = '/'))
    in

    let%bind path, seenPathSep = path in
    if not requirePathSep || seenPathSep
    then return (make path)
    else fail "not a path"

  let path =
    let make path manifest =
      LocalPath { path; manifest; }
    in
    pathLike make

  let noSource =
    let%bind () = ignore (string "no-source:") in
    return NoSource

  let parser =
    withPrefix "git:" git
    <|> withPrefix "github:" github
    <|> withPrefix "gh:" github
    <|> withPrefix "archive:" archive
    <|> withPrefix "path:" (path ~requirePathSep:false)
    <|> noSource

  let parserRelaxed =
    archive
    <|> github
    <|> (path ~requirePathSep:true)
end

let parser = Parse.parser
let parserRelaxed = Parse.parserRelaxed
let parse = Parse.(parse parser)
let parseRelaxed = Parse.(parse parserRelaxed)

let to_yojson v =
  `String (show v)

let of_yojson json =
  match json with
  | `String string ->
    parse string
  | _ -> Error "expected string"

let relaxed_of_yojson json =
  match json with
  | `String string ->
    let parse = Parse.(parse (parser <|> parserRelaxed)) in
    parse string
  | _ -> Error "expected string"
