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
  [@@deriving ord]

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

  let github =
    let prefix = string "github:" <|> string "gh:" in
    let user = take_while1 (fun c -> c <> '/') <?> "user" in
    let repo = take_while1 (fun c -> c <> '#' && c <> ':') <?> "repo" in
    let commit = (char '#' *> take_while1 (fun _ -> true)) <|> fail "missing commit" in
    let manifest = maybe (char ':' *> manifestFilenameBeforeSharp) in
    let make user repo manifest commit =
      Github { user; repo; commit; manifest; }
    in
    prefix *> (make <$> (user <* char '/') <*> repo <*> manifest <*> commit)

  let git =
    let prefix = string "git:" in
    let proto = take_while1 (fun c -> c <> ':') in
    let remote = take_while1 (fun c -> c <> '#' && c <> ':') in
    let commit = char '#' *> take_while1 (fun c -> c <> '&') <|> fail "missing commit" in
    let manifest = maybe (char ':' *> manifestFilenameBeforeSharp) in
    let make proto remote manifest commit =
      Git { remote = proto ^ ":" ^ remote; commit; manifest; }
    in
    prefix *> (make <$> proto <* char ':' <*> remote <*> manifest <*> commit)

  let archive =
    let prefix = string "archive:" in
    let remote = take_while1 (fun c -> c <> '#') in
    let make url checksum =
      Archive { url; checksum; }
    in
    prefix *> (lift2 make) (remote <* char '#') Checksum.parser

  let pathLike ~prefix make =
    let path = take_while1 (fun c -> c <> '#') in
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
    prefix *> (make <$> path)

  let path =
    let make path manifest =
      LocalPath { path; manifest; }
    in
    pathLike ~prefix:(string "path:") make

  let link =
    let make path manifest =
      LocalPathLink { path; manifest; }
    in
    pathLike ~prefix:(string "link:") make

  let noSource =
    let%bind () = ignore (string "no-source:") in
    return NoSource

  let parser = github <|> git <|> archive <|> path <|> link <|> noSource
end

let parser = Parse.parser
let parse = Parse.(parse parser)

let%test_module "parsing" = (module struct

  let expectParses =
    Parse.Test.expectParses ~pp ~compare parse

  let%test "github:user/repo#commit" =
    expectParses
      "github:user/repo#commit"
      (Github {user = "user"; repo = "repo"; commit = "commit"; manifest = None})

  let%test "github:user/repo/lwt.opam#commit" =
    expectParses
      "github:user/repo:lwt.opam#commit"
      (Github {
        user = "user";
        repo = "repo";
        commit = "commit";
        manifest = Some (ManifestSpec.Filename.ofStringExn "lwt.opam");
      })

  let%test "gh:user/repo#commit" =
    expectParses
      "gh:user/repo#commit"
      (Github {user = "user"; repo = "repo"; commit = "commit"; manifest = None})

  let%test "gh:user/repo:lwt.opam#commit" =
    expectParses
      "gh:user/repo:lwt.opam#commit"
      (Github {
        user = "user";
        repo = "repo";
        commit = "commit";
        manifest = Some (ManifestSpec.Filename.ofStringExn "lwt.opam");
      })

  let%test "git:http://example.com/repo#commit" =
    expectParses
      "git:http://example.com/repo#commit"
      (Git {remote = "http://example.com/repo"; commit = "commit"; manifest = None})

  let%test "git:http://example.com/repo:lwt.opam#commit" =
    expectParses
      "git:http://example.com/repo:lwt.opam#commit"
      (Git {
        remote = "http://example.com/repo";
        commit = "commit";
        manifest = Some (ManifestSpec.Filename.ofStringExn "lwt.opam");
      })

  let%test "git:git://example.com/repo:lwt.opam#commit" =
    expectParses
      "git:git://example.com/repo:lwt.opam#commit"
      (Git {
        remote = "git://example.com/repo";
        commit = "commit";
        manifest = Some (ManifestSpec.Filename.ofStringExn "lwt.opam");
      })

  let%test "archive:http://example.com#abc123" =
    expectParses
      "archive:http://example.com#abc123"
      (Archive {url = "http://example.com"; checksum = Checksum.Sha1, "abc123";})

  let%test "archive:https://example.com#abc123" =
    expectParses
      "archive:https://example.com#abc123"
      (Archive {url = "https://example.com"; checksum = Checksum.Sha1, "abc123";})

  let%test "archive:https://example.com#md5:abc123" =
    expectParses
      "archive:https://example.com#md5:abc123"
      (Archive {url = "https://example.com"; checksum = Checksum.Md5, "abc123";})

  let%test "path:/some/path" =
    expectParses
      "path:/some/path"
      (LocalPath {path = Path.v "/some/path"; manifest = None;})

  let%test "path:/some/path/lwt.opam" =
    expectParses
      "path:/some/path/lwt.opam"
      (LocalPath {
        path = Path.v "/some/path";
        manifest = Some (ManifestSpec.Filename.ofStringExn "lwt.opam");
      })

  let%test "link:/some/path" =
    expectParses
      "link:/some/path"
      (LocalPathLink {path = Path.v "/some/path"; manifest = None;})

  let%test "link:/some/path/lwt.opam" =
    expectParses
      "link:/some/path/lwt.opam"
      (LocalPathLink {
        path = Path.v "/some/path";
        manifest = Some (ManifestSpec.Filename.ofStringExn "lwt.opam");
      })

  let%test "no-source:" =
    expectParses
      "no-source:"
      NoSource

end)

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
