module MS = SandboxSpec.ManifestSpec

include Metadata.Source

let showOrig = function
  | Github {user; repo; commit; manifest = None;} ->
    Printf.sprintf "github:%s/%s#%s" user repo commit
  | Github {user; repo; commit; manifest = Some manifest;} ->
    Printf.sprintf "github:%s/%s:%s#%s" user repo (MS.show manifest) commit
  | Git {remote; commit; manifest = None;} ->
    Printf.sprintf "git:%s#%s" remote commit
  | Git {remote; commit; manifest = Some manifest;} ->
    Printf.sprintf "git:%s:%s#%s" remote (MS.show manifest) commit
  | Archive {url; checksum} ->
    Printf.sprintf "archive:%s#%s" url (Checksum.show checksum)
  | LocalPath {path; manifest = None;} ->
    Printf.sprintf "path:%s" (Path.show path)
  | LocalPath {path; manifest = Some manifest;} ->
    Printf.sprintf "path:%s/%s" (Path.show path) (MS.show manifest)
  | LocalPathLink {path; manifest = None;} ->
    Printf.sprintf "link:%s" (Path.show path)
  | LocalPathLink {path; manifest = Some manifest;} ->
    Printf.sprintf "link:%s/%s" (Path.show path) (MS.show manifest)
  | NoSource -> "no-source:"

let show = function
  | Orig source -> showOrig source
  | Override {source; _} -> "override:" ^ showOrig source

let pp fmt src =
  Fmt.pf fmt "%s" (show src)

module Parse = struct
  include Parse

  let manifestFilenameBeforeSharp =
    till (fun c -> c <> '#') MS.parser

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
        match MS.ofString (Path.basename path) with
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

  let origSource = github <|> git <|> archive <|> path <|> link <|> noSource
  let source =
    let%bind source = origSource in
    return (Orig source)
end

let parser = Parse.source
let parse = Parse.(parse parser)

let%test_module "parsing" = (module struct

  let expectParses =
    Parse.Test.expectParses ~pp ~equal parse

  let%test "github:user/repo#commit" =
    expectParses
      "github:user/repo#commit"
      (Orig (Github {
        user = "user";
        repo = "repo";
        commit = "commit";
        manifest = None;
      }))

  let%test "github:user/repo/lwt.opam#commit" =
    expectParses
      "github:user/repo:lwt.opam#commit"
      (Orig (Github {
        user = "user";
        repo = "repo";
        commit = "commit";
        manifest = Some (MS.ofStringExn "lwt.opam");
      }))

  let%test "gh:user/repo#commit" =
    expectParses
      "gh:user/repo#commit"
      (Orig (Github {
        user = "user";
        repo = "repo";
        commit = "commit";
        manifest = None;
      }))

  let%test "gh:user/repo:lwt.opam#commit" =
    expectParses
      "gh:user/repo:lwt.opam#commit"
      (Orig (Github {
        user = "user";
        repo = "repo";
        commit = "commit";
        manifest = Some (MS.ofStringExn "lwt.opam");
      }))

  let%test "git:http://example.com/repo#commit" =
    expectParses
      "git:http://example.com/repo#commit"
      (Orig (Git {
        remote = "http://example.com/repo";
        commit = "commit";
        manifest = None;
      }))

  let%test "git:http://example.com/repo:lwt.opam#commit" =
    expectParses
      "git:http://example.com/repo:lwt.opam#commit"
      (Orig (Git {
        remote = "http://example.com/repo";
        commit = "commit";
        manifest = Some (MS.ofStringExn "lwt.opam");
      }))

  let%test "git:git://example.com/repo:lwt.opam#commit" =
    expectParses
      "git:git://example.com/repo:lwt.opam#commit"
      (Orig (Git {
        remote = "git://example.com/repo";
        commit = "commit";
        manifest = Some (MS.ofStringExn "lwt.opam");
      }))

  let%test "archive:http://example.com#abc123" =
    expectParses
      "archive:http://example.com#abc123"
      (Orig (Archive {
        url = "http://example.com";
        checksum = Checksum.Sha1, "abc123";
      }))

  let%test "archive:https://example.com#abc123" =
    expectParses
      "archive:https://example.com#abc123"
      (Orig (Archive {
        url = "https://example.com";
        checksum = Checksum.Sha1, "abc123";
      }))

  let%test "archive:https://example.com#md5:abc123" =
    expectParses
      "archive:https://example.com#md5:abc123"
      (Orig (Archive {
        url = "https://example.com";
        checksum = Checksum.Md5, "abc123";
      }))

  let%test "path:/some/path" =
    expectParses
      "path:/some/path"
      (Orig (LocalPath {path = Path.v "/some/path"; manifest = None;}))

  let%test "path:/some/path/lwt.opam" =
    expectParses
      "path:/some/path/lwt.opam"
      (Orig (LocalPath {
        path = Path.v "/some/path";
        manifest = Some (MS.ofStringExn "lwt.opam");
      }))

  let%test "link:/some/path" =
    expectParses
      "link:/some/path"
      (Orig (LocalPathLink {path = Path.v "/some/path"; manifest = None;}))

  let%test "link:/some/path/lwt.opam" =
    expectParses
      "link:/some/path/lwt.opam"
      (Orig (LocalPathLink {
        path = Path.v "/some/path";
        manifest = Some (MS.ofStringExn "lwt.opam");
      }))

  let%test "no-source:" =
    expectParses
      "no-source:"
      (Orig NoSource)

end)

let override_of_yojson =
  let make name version build install =
    {Metadata.SourceOverride. name; version; build; install}
  in
  Json.Decode.(
    return make
    <*> fieldOpt ~name:"name" string
    <*> fieldOpt ~name:"version" string
    <*> fieldOpt ~name:"build" (list (list string))
    <*> fieldOpt ~name:"install" (list (list string))
  )

let%test "override_of_yojson" =
  let json = Yojson.Safe.from_string {|{}|} in
  override_of_yojson json = Ok {
    Metadata.SourceOverride.
    name = None;
    version = None;
    install = None;
    build = None;
  }

let%test "override_of_yojson" =
  let json = Yojson.Safe.from_string {|{build: [[]]}|} in
  override_of_yojson json = Ok {
    Metadata.SourceOverride.
    name = None;
    version = None;
    install = None;
    build = Some [[]];
  }

let override_to_yojson (override : Metadata.SourceOverride.t) =
  let fields = [] in
  let fields =
    match override.name with
    | None -> fields
    | Some name -> ("name", `String name)::fields
  in
  let fields =
    match override.version with
    | None -> fields
    | Some version -> ("version", `String version)::fields
  in
  let fields =
    match override.build with
    | None -> fields
    | Some build -> ("build", Json.Encode.(list (list string)) build)::fields
  in
  let fields =
    match override.install with
    | None -> fields
    | Some install -> ("install", Json.Encode.(list (list string)) install)::fields
  in
  `Assoc fields

let to_yojson v =
  match v with
  | Orig source -> `String (showOrig source)
  | Override {source; override} ->
    `Assoc [
      "source", `String (showOrig source);
      "override", override_to_yojson override;
    ]

let of_yojson json =
  let open Result.Syntax in
  match json with
  | `String string -> parse string
  | `Assoc _ ->
    let%bind origSource = Json.Decode.(field ~name:"source" string) json in
    let%bind origSource = Parse.(parse origSource) origSource in
    let%bind override = Json.Decode.(field ~name:"override") override_of_yojson json in
    return (Override {source = origSource; override})
  | _ -> Error "expected string"

module Map = Map.Make(struct
  type nonrec t = t
  let compare = compare
end)

module Set = Set.Make(struct
  type nonrec t = t
  let compare = compare
end)
