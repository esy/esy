type t =
  | Archive of {
      url : string;
      checksum : Checksum.t;
    }
  | Git of {
      remote : string;
      commit : string;
      manifestFilename : string option;
    }
  | Github of {
      user : string;
      repo : string;
      commit : string;
      manifestFilename : string option;
    }
  | LocalPath of {
      path : Path.t;
      manifestFilename : string option;
    }
  | LocalPathLink of {
      path : Path.t;
      manifestFilename : string option;
    }
  | NoSource
  [@@deriving (ord, eq)]

let toString = function
  | Github {user; repo; commit; manifestFilename = None;} ->
    Printf.sprintf "github:%s/%s#%s" user repo commit
  | Github {user; repo; commit; manifestFilename = Some manifestFilename;} ->
    Printf.sprintf "github:%s/%s:%s#%s" user repo manifestFilename commit
  | Git {remote; commit; manifestFilename = None;} ->
    Printf.sprintf "git:%s#%s" remote commit
  | Git {remote; commit; manifestFilename = Some manifestFilename;} ->
    Printf.sprintf "git:%s:%s#%s" remote manifestFilename commit
  | Archive {url; checksum} ->
    Printf.sprintf "archive:%s#%s" url (Checksum.show checksum)
  | LocalPath {path; manifestFilename = None;} ->
    Printf.sprintf "path:%s" (Path.toString path)
  | LocalPath {path; manifestFilename = Some manifestFilename;} ->
    Printf.sprintf "path:%s/%s" (Path.toString path) manifestFilename
  | LocalPathLink {path; manifestFilename = None;} ->
    Printf.sprintf "link:%s" (Path.toString path)
  | LocalPathLink {path; manifestFilename = Some manifestFilename;} ->
    Printf.sprintf "link:%s/%s" (Path.toString path) manifestFilename
  | NoSource -> "no-source:"

let show = toString

let pp fmt src =
  Fmt.pf fmt "%s" (toString src)

module Parse = struct
  include Parse

  let github =
    let prefix = string "github:" <|> string "gh:" in
    let user = take_while1 (fun c -> c <> '/') <?> "user" in
    let repo = take_while1 (fun c -> c <> '#' && c <> ':') <?> "repo" in
    let commit = (char '#' *> take_while1 (fun _ -> true)) <|> fail "missing commit" in
    let manifestFilename = maybe (char ':' *> take_while1 (fun c -> c <> '#')) in
    let make user repo manifestFilename commit =
      Github { user; repo; commit; manifestFilename; }
    in
    prefix *> (make <$> (user <* char '/') <*> repo <*> manifestFilename <*> commit)

  let git =
    let prefix = string "git:" in
    let proto = take_while1 (fun c -> c <> ':') in
    let remote = take_while1 (fun c -> c <> '#' && c <> ':') in
    let commit = char '#' *> take_while1 (fun c -> c <> '&') <|> fail "missing commit" in
    let manifestFilename = maybe (char ':' *> take_while1 (fun c -> c <> '#')) in
    let make proto remote manifestFilename commit =
      Git { remote = proto ^ ":" ^ remote; commit; manifestFilename; }
    in
    prefix *> (make <$> proto <* char ':' <*> remote <*> manifestFilename <*> commit)

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
      let path, manifestFilename =
        let basename = Path.basename path in
        match basename, Path.getExt path with
        | _, ".opam" | _, ".json" | "opam", "" ->
          Path.(remEmptySeg (parent path)), Some basename
        | _ -> path, None
      in
      make path manifestFilename
    in
    prefix *> (make <$> path)

  let path =
    let make path manifestFilename =
      LocalPath { path; manifestFilename; }
    in
    pathLike ~prefix:(string "path:") make

  let link =
    let make path manifestFilename =
      LocalPathLink { path; manifestFilename; }
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
    Parse.Test.expectParses ~pp ~equal parse

  let%test "github:user/repo#commit" =
    expectParses
      "github:user/repo#commit"
      (Github {user = "user"; repo = "repo"; commit = "commit"; manifestFilename = None})

  let%test "github:user/repo/lwt.opam#commit" =
    expectParses
      "github:user/repo:lwt.opam#commit"
      (Github {user = "user"; repo = "repo"; commit = "commit"; manifestFilename = Some "lwt.opam"})

  let%test "gh:user/repo#commit" =
    expectParses
      "gh:user/repo#commit"
      (Github {user = "user"; repo = "repo"; commit = "commit"; manifestFilename = None})

  let%test "gh:user/repo:lwt.opam#commit" =
    expectParses
      "gh:user/repo:lwt.opam#commit"
      (Github {user = "user"; repo = "repo"; commit = "commit"; manifestFilename = Some "lwt.opam"})

  let%test "git:http://example.com/repo#commit" =
    expectParses
      "git:http://example.com/repo#commit"
      (Git {remote = "http://example.com/repo"; commit = "commit"; manifestFilename = None})

  let%test "git:http://example.com/repo:lwt.opam#commit" =
    expectParses
      "git:http://example.com/repo:lwt.opam#commit"
      (Git {remote = "http://example.com/repo"; commit = "commit"; manifestFilename = Some "lwt.opam"})

  let%test "git:git://example.com/repo:lwt.opam#commit" =
    expectParses
      "git:git://example.com/repo:lwt.opam#commit"
      (Git {remote = "git://example.com/repo"; commit = "commit"; manifestFilename = Some "lwt.opam"})

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
      (LocalPath {path = Path.v "/some/path"; manifestFilename = None;})

  let%test "path:/some/path/lwt.opam" =
    expectParses
      "path:/some/path/lwt.opam"
      (LocalPath {path = Path.v "/some/path"; manifestFilename = Some "lwt.opam";})

  let%test "link:/some/path" =
    expectParses
      "link:/some/path"
      (LocalPathLink {path = Path.v "/some/path"; manifestFilename = None;})

  let%test "link:/some/path/lwt.opam" =
    expectParses
      "link:/some/path/lwt.opam"
      (LocalPathLink {path = Path.v "/some/path"; manifestFilename = Some "lwt.opam";})

  let%test "no-source:" =
    expectParses
      "no-source:"
      NoSource

end)

let to_yojson v =
  `String (toString v)

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
