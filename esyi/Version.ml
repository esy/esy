type t =
  | Npm of SemverVersion.Version.t
  | Opam of OpamPackageVersion.Version.t
  | Source of Source.t
  [@@deriving ord, sexp_of]

let show v =
  match v with
  | Npm t -> SemverVersion.Version.show t
  | Opam v -> "opam:" ^ OpamPackageVersion.Version.show v
  | Source src -> (Source.show src)

let pp fmt v =
  Fmt.fmt "%s" fmt (show v)

module Parse = struct
  include Parse

  let npm =
    let%map v = SemverVersion.Version.parser in
    Npm v

  let opam =
    let%map v = OpamPackageVersion.Version.parser in
    Opam v

  let opamWithPrefix =
    string "opam:" *> opam

  let source =
    let%map source = Source.parser in
    Source source

  let sourceRelaxed =
    let%map source = Source.parserRelaxed in
    Source source
end

let parse ?(tryAsOpam=false) =
  let parser =
    if tryAsOpam
    then Parse.(source <|> opamWithPrefix <|> opam <|> sourceRelaxed)
    else Parse.(source <|> opamWithPrefix <|> npm <|> sourceRelaxed)
  in
  Parse.parse parser

let%test_module "parsing" = (module struct

  let parse ?tryAsOpam =
    Parse.Test.parse ~sexp_of:sexp_of_t (parse ?tryAsOpam)

  let%expect_test "1.0.0" =
    parse "1.0.0";
    [%expect {| (Npm ((major 1) (minor 0) (patch 0) (prerelease ()) (build ()))) |}]

  let%expect_test "opam:1.0.0" =
    parse "opam:1.0.0";
    [%expect {| (Opam (Opam 1.0.0)) |}]

  let%expect_test "1.0.0" =
    parse ~tryAsOpam:true "1.0.0";
    [%expect {| (Opam (Opam 1.0.0)) |}]

  let%expect_test "1.0.0" =
    parse ~tryAsOpam:true "opam:1.0.0";
    [%expect {| (Opam (Opam 1.0.0)) |}]

  let%expect_test "no-source:" =
    parse "no-source:";
    [%expect {| (Source NoSource) |}]

  let%expect_test "no-source:" =
    parse ~tryAsOpam:true "no-source:";
    [%expect {| (Source NoSource) |}]

  let%expect_test "user/repo#commit" =
    parse "user/repo#commit";
    [%expect {| (Source (Github (user user) (repo repo) (commit commit) (manifest ()))) |}]

  let%expect_test "user/repo#commit" =
    parse ~tryAsOpam:true "user/repo#commit";
    [%expect {| (Source (Github (user user) (repo repo) (commit commit) (manifest ()))) |}]

  let%expect_test "./some/path" =
    parse "./some/path";
    [%expect {| (Source (LocalPath (path some/path) (manifest ()))) |}]

  let%expect_test "./some/path" =
    parse ~tryAsOpam:true "./some/path";
    [%expect {| (Source (LocalPath (path some/path) (manifest ()))) |}]

  let%expect_test "/some/path" =
    parse "/some/path";
    [%expect {| (Source (LocalPath (path /some/path) (manifest ()))) |}]

  let%expect_test "/some/path" =
    parse ~tryAsOpam:true "/some/path";
    [%expect {| (Source (LocalPath (path /some/path) (manifest ()))) |}]

  let%expect_test "some/path" =
    parse "some/path";
    [%expect {| (Source (LocalPath (path some/path) (manifest ()))) |}]

  let%expect_test "some/path" =
    parse ~tryAsOpam:true "some/path";
    [%expect {| (Source (LocalPath (path some/path) (manifest ()))) |}]

  let%expect_test "some" =
    parse "some";
    [%expect {| Error parsing 'some': : not a path |}]

  let%expect_test "some" =
    parse ~tryAsOpam:true "some";
    [%expect {| (Opam (Opam some)) |}]
end)

let parseExn v =
  match parse v with
  | Ok v -> v
  | Error err -> failwith err

let to_yojson v = `String (show v)

let of_yojson json =
  let open Result.Syntax in
  let%bind v = Json.Decode.string json in
  parse v

module Map = Map.Make(struct
  type nonrec t = t
  let compare = compare
end)

module Set = Set.Make(struct
  type nonrec t = t
  let compare = compare
end)
