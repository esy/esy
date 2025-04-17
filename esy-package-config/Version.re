[@deriving (ord, sexp_of)]
type t =
  | Npm(SemverVersion.Version.t)
  | Opam(OpamPackageVersion.Version.t)
  | Source(Source.t);

let show = v =>
  switch (v) {
  | Npm(t) => SemverVersion.Version.show(t)
  | Opam(v) => "opam:" ++ OpamPackageVersion.Version.show(v)
  | Source(src) => Source.show(src)
  };

let showSimple = v =>
  switch (v) {
  | Npm(t) => SemverVersion.Version.show(t)
  | Opam(v) => OpamPackageVersion.Version.show(v)
  | Source(src) => Source.show(src)
  };

let pp = (fmt, v) => Fmt.fmt("%s", fmt, show(v));

module Parse = {
  include Parse;

  let npm = {
    let%map v = SemverVersion.Version.parser;
    Npm(v);
  };

  let opam = {
    let%map v = OpamPackageVersion.Version.parser;
    Opam(v);
  };

  let opamWithPrefix = string("opam:") *> commit >> opam;

  let sourceRelaxed = {
    let%map source = Source.parserRelaxed;
    Source(source);
  };
};

let parse = (~tryAsOpam=false, v) => {
  let parser =
    if (tryAsOpam) {
      Parse.(opamWithPrefix <|> opam <|> sourceRelaxed);
    } else {
      Parse.(opamWithPrefix <|> npm <|> sourceRelaxed);
    };
  Parse.parse(parser, v);
};

let%test_module "parsing" =
  (module
   {
     let parse = (~tryAsOpam=?) =>
       Parse.Test.parse(~sexp_of=sexp_of_t, parse(~tryAsOpam?));

     let%expect_test "1.0.0" = {
       parse("1.0.0");
       [%expect
        {| (Npm ((major 1) (minor 0) (patch 0) (prerelease ()) (build ()))) |}
       ];
     };

     let%expect_test "opam:1.0.0" = {
       parse("opam:1.0.0");
       [%expect {| (Opam (Opam 1.0.0)) |}];
     };

     let%expect_test "1.0.0" = {
       parse(~tryAsOpam=true, "1.0.0");
       [%expect {| (Opam (Opam 1.0.0)) |}];
     };

     let%expect_test "1.0.0" = {
       parse(~tryAsOpam=true, "opam:1.0.0");
       [%expect {| (Opam (Opam 1.0.0)) |}];
     };

     let%expect_test "no-source:" = {
       parse("no-source:");
       [%expect {| (Source (Dist NoSource)) |}];
     };

     let%expect_test "no-source:" = {
       parse(~tryAsOpam=true, "no-source:");
       [%expect {| (Source (Dist NoSource)) |}];
     };

     let%expect_test "user/repo#abc123" = {
       parse("user/repo#abc123");
       [%expect
        {|
      (Source
       (Dist (Github (user user) (repo repo) (commit abc123) (manifest ())))) |}
       ];
     };

     let%expect_test "user/repo#abc123" = {
       parse(~tryAsOpam=true, "user/repo#abc123");
       [%expect
        {|
      (Source
       (Dist (Github (user user) (repo repo) (commit abc123) (manifest ())))) |}
       ];
     };

     let%expect_test "./some/path" = {
       parse("./some/path");
       [%expect
        {| (Source (Dist (LocalPath ((path some/path) (manifest ()))))) |}
       ];
     };

     let%expect_test "./some/path" = {
       parse(~tryAsOpam=true, "./some/path");
       [%expect
        {| (Source (Dist (LocalPath ((path some/path) (manifest ()))))) |}
       ];
     };

     let%expect_test "/some/path" = {
       parse("/some/path");
       [%expect
        {| (Source (Dist (LocalPath ((path /some/path) (manifest ()))))) |}
       ];
     };

     let%expect_test "/some/path" = {
       parse(~tryAsOpam=true, "/some/path");
       [%expect
        {| (Source (Dist (LocalPath ((path /some/path) (manifest ()))))) |}
       ];
     };

     let%expect_test "link:/some/path" = {
       parse("link:/some/path");
       [%expect
        {| (Source (Link (path /some/path) (manifest ()) (kind LinkRegular))) |}
       ];
     };

     let%expect_test "link:/some/path" = {
       parse(~tryAsOpam=true, "link:/some/path");
       [%expect
        {| (Source (Link (path /some/path) (manifest ()) (kind LinkRegular))) |}
       ];
     };

     let%expect_test "some/path" = {
       parse("some/path");
       [%expect
        {| (Source (Dist (LocalPath ((path some/path) (manifest ()))))) |}
       ];
     };

     let%expect_test "some/path" = {
       parse(~tryAsOpam=true, "some/path");
       [%expect
        {| (Source (Dist (LocalPath ((path some/path) (manifest ()))))) |}
       ];
     };

     let%expect_test "some" = {
       parse("some");
       [%expect {| ERROR: parsing "some": : not a path |}];
     };

     let%expect_test "some" = {
       parse(~tryAsOpam=true, "some");
       [%expect {| (Opam (Opam some)) |}];
     };
   });

let parseExn = v =>
  switch (parse(v)) {
  | Ok(v) => v
  | Error(err) => failwith(err)
  };

let to_yojson = v => `String(show(v));

let of_yojson = json => {
  open Result.Syntax;
  let* v = Json.Decode.string(json);
  parse(v);
};

module Map =
  Map.Make({
    type nonrec t = t;
    let compare = compare;
  });

module Set =
  Set.Make({
    type nonrec t = t;
    let compare = compare;
  });
