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
      path : Path.t;
      manifest : ManifestSpec.Filename.t option;
    }
  | LocalPathLink of {
      path : Path.t;
      manifest : ManifestSpec.Filename.t option;
    }
  | NoSource
  [@@deriving ord, sexp_of]

let manifest (src : t) =
  match src with
  | Git info -> info.manifest
  | Github info -> info.manifest
  | LocalPath info -> info.manifest
  | LocalPathLink info -> info.manifest
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
    Printf.sprintf "path:%s/%s" (showPath path) (ManifestSpec.Filename.show manifest)
  | LocalPathLink {path; manifest = None;} ->
    Printf.sprintf "link:%s" (showPath path)
  | LocalPathLink {path; manifest = Some manifest;} ->
    Printf.sprintf "link:%s/%s" (showPath path) (ManifestSpec.Filename.show manifest)
  | NoSource -> "no-source:"

let show = show' ~showPath:Path.show
let showPretty = show' ~showPath:Path.showPretty

let pp fmt src =
  Fmt.pf fmt "%s" (show src)

let ppPretty fmt src =
  Fmt.pf fmt "%s" (showPretty src)

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
        match ManifestSpec.Filename.ofString (Path.basename path) with
        | Ok manifest ->
          let path = Path.(remEmptySeg (parent path)) in
          path, Some manifest
        | Error _ ->
          path, None
      in
      make path manifest
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

  let link =
    let make path manifest =
      LocalPathLink { path; manifest; }
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
    <|> withPrefix "link:" (link ~requirePathSep:false)
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
  | `String string -> parse string
  | _ -> Error "expected string"

module Map = Map.Make(struct
  type nonrec t = t
  let compare = compare
end)

module Set = Set.Make(struct
  type nonrec t = t
  let compare = compare
end)

let%test_module "parsing" = (module struct

  let parse =
    Parse.Test.parse ~sexp_of:sexp_of_t parse

  let%expect_test "github:user/repo#commit" =
    parse "github:user/repo#commit";
    [%expect {| (Github (user user) (repo repo) (commit commit) (manifest ())) |}]

  let%expect_test "github:user/repo:lwt.opam#commit" =
    parse "github:user/repo:lwt.opam#commit";
    [%expect {| (Github (user user) (repo repo) (commit commit) (manifest ((Opam lwt.opam)))) |}]

  let%expect_test "gh:user/repo#commit" =
    parse "gh:user/repo#commit";
    [%expect {| (Github (user user) (repo repo) (commit commit) (manifest ())) |}]

  let%expect_test "gh:user/repo:lwt.opam#commit" =
    parse "gh:user/repo:lwt.opam#commit";
    [%expect {| (Github (user user) (repo repo) (commit commit) (manifest ((Opam lwt.opam)))) |}]

  let%expect_test "git:http://example.com/repo#commit" =
    parse "git:http://example.com/repo#commit";
    [%expect {| (Git (remote http://example.com/repo) (commit commit) (manifest ())) |}]

  let%expect_test "git:http://example.com/repo:lwt.opam#commit" =
    parse "git:http://example.com/repo:lwt.opam#commit";
    [%expect {|
      (Git (remote http://example.com/repo) (commit commit)
       (manifest ((Opam lwt.opam)))) |}]

  let%expect_test "git:git://example.com/repo:lwt.opam#commit" =
    parse "git:git://example.com/repo:lwt.opam#commit";
    [%expect {|
      (Git (remote git://example.com/repo) (commit commit)
       (manifest ((Opam lwt.opam)))) |}]

  let%expect_test "archive:http://example.com#abc123" =
    parse "archive:http://example.com#abc123";
    [%expect {| (Archive (url http://example.com) (checksum (Sha1 abc123))) |}]

  let%expect_test "archive:https://example.com#abc123" =
    parse "archive:https://example.com#abc123";
    [%expect {| (Archive (url https://example.com) (checksum (Sha1 abc123))) |}]

  let%expect_test "archive:https://example.com#md5:abc123" =
    parse "archive:https://example.com#md5:abc123";
    [%expect {| (Archive (url https://example.com) (checksum (Md5 abc123))) |}]

  let%expect_test "path:/some/path" =
    parse "path:/some/path";
    [%expect {| (LocalPath (path /some/path) (manifest ())) |}]

  let%expect_test "path:/some/path/lwt.opam" =
    parse "path:/some/path/lwt.opam";
    [%expect {| (LocalPath (path /some/path) (manifest ((Opam lwt.opam)))) |}]

  let%expect_test "link:/some/path" =
    parse "link:/some/path";
    [%expect {| (LocalPathLink (path /some/path) (manifest ())) |}]

  let%expect_test "link:/some/path/lwt.opam" =
    parse "link:/some/path/lwt.opam";
    [%expect {| (LocalPathLink (path /some/path) (manifest ((Opam lwt.opam)))) |}]

  let%expect_test "path:some" =
    parse "path:some";
    [%expect {| (LocalPath (path some) (manifest ())) |}]

  let%expect_test "link:some" =
    parse "link:some";
    [%expect {| (LocalPathLink (path some) (manifest ())) |}]

  let%expect_test "no-source:" =
    parse "no-source:";
    [%expect {| NoSource |}]

  let parseRelaxedd =
    Parse.Test.parse ~sexp_of:sexp_of_t parseRelaxed

  let%expect_test "user/repo#commit" =
    parseRelaxedd "user/repo#commit";
    [%expect {| (Github (user user) (repo repo) (commit commit) (manifest ())) |}]

  let%expect_test "user/repo:lwt.opam#commit" =
    parseRelaxedd "user/repo:lwt.opam#commit";
    [%expect {| (Github (user user) (repo repo) (commit commit) (manifest ((Opam lwt.opam)))) |}]

  let%expect_test "http://example.com#abc123" =
    parseRelaxedd "http://example.com#abc123";
    [%expect {| (Archive (url http://example.com) (checksum (Sha1 abc123))) |}]

  let%expect_test "https://example.com#abc123" =
    parseRelaxedd "https://example.com#abc123";
    [%expect {| (Archive (url https://example.com) (checksum (Sha1 abc123))) |}]

  let%expect_test "https://example.com#md5:abc123" =
    parseRelaxedd "https://example.com#md5:abc123";
    [%expect {| (Archive (url https://example.com) (checksum (Md5 abc123))) |}]

  let%expect_test "/some/path" =
    parseRelaxedd "/some/path";
    [%expect {| (LocalPath (path /some/path) (manifest ())) |}]

  let%expect_test "some" =
    parseRelaxedd "some";
    [%expect {| Error parsing 'some': : not a path |}]

end)
