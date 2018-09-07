type t = {
  name: string;
  spec: VersionSpec.t;
} [@@deriving (eq, ord)]

let toString {name; spec} =
  name ^ "@" ^ (VersionSpec.toString spec)

let show = toString

let to_yojson req =
  `String (toString req)

let pp fmt req =
  Fmt.fmt "%s" fmt (toString req)

let matches ~name ~version req =
  name = req.name && VersionSpec.matches ~version req.spec

let parse =
  let name = Tyre.pcre {|[^@]+|} in
  let opamscope = Tyre.(str "@opam/" *> name) in
  let npmscope = Tyre.(seq (str "@" *> name) (str "/" *> name)) in
  let spec = Tyre.(str "@" *> pcre ".*") in
  let opamWithSpec = Tyre.(start *> seq opamscope spec <* stop) in
  let opamWithoutSpec = Tyre.(start *> opamscope <* stop) in
  let npmScopeWithSpec = Tyre.(start *> seq npmscope spec <* stop) in
  let npmScopeWithoutSpec = Tyre.(start *> npmscope <* stop) in
  let npmWithSpec = Tyre.(start *> seq name spec <* stop) in
  let npmWithoutSpec = Tyre.(start *> name <* stop) in
  let open Result.Syntax in
  let re = Tyre.(route [
    (opamWithSpec --> function
      | opamname, "" ->
        let spec = VersionSpec.Opam [[OpamPackageVersion.Constraint.ANY]] in
        return {name = "@opam/" ^ opamname; spec};
      | opamname, spec ->
        let%bind spec = VersionSpec.parseAsOpam spec in
        return {name = "@opam/" ^ opamname; spec});
    (npmScopeWithSpec --> function
      | (scope, name), "" ->
        let spec = VersionSpec.Npm [[SemverVersion.Constraint.ANY]] in
        return {name = "@" ^ scope ^ "/" ^ name; spec};
      | (scope, name), spec ->
        let%bind spec = VersionSpec.parseAsNpm spec in
        return {name = "@" ^ scope ^ "/" ^ name; spec});
    (npmWithSpec --> function
      | name, "" ->
        let spec = VersionSpec.Npm [[SemverVersion.Constraint.ANY]] in
        return {name; spec};
      | name, spec ->
        let%bind spec = VersionSpec.parseAsNpm spec in
        return {name; spec});
    (opamWithoutSpec --> fun opamname ->
        let spec = VersionSpec.Opam [[OpamPackageVersion.Constraint.ANY]] in
        return {name = "@opam/" ^ opamname; spec});
    (npmScopeWithoutSpec --> function
      | (scope, name) ->
        let spec = VersionSpec.Npm [[SemverVersion.Constraint.ANY]] in
        return {name = "@" ^ scope ^ "/" ^ name; spec});
    (npmWithoutSpec --> function
      | name ->
        let spec = VersionSpec.Npm [[SemverVersion.Constraint.ANY]] in
        return {name; spec});
  ]) in
  let parse spec =
    match Tyre.exec re spec with
    | Ok (Ok v) -> Ok v
    | Ok (Error err) -> Error err
    | Error (`ConverterFailure _) -> Error "error parsing"
    | Error (`NoMatch _) -> Error "error parsing"
  in
  parse

let%test_module "parsing" = (module struct

  let cases = [
    "name",
    {
      name = "name";
      spec = VersionSpec.Npm [[SemverVersion.Constraint.ANY]];
    };
    "name@",
    {
      name = "name";
      spec = VersionSpec.Npm [[SemverVersion.Constraint.ANY]];
    };
    "name@*",
    {
      name = "name";
      spec = VersionSpec.Npm [[SemverVersion.Constraint.ANY]];
    };

    "@scope/name",
    {
      name = "@scope/name";
      spec = VersionSpec.Npm [[SemverVersion.Constraint.ANY]];
    };
    "@scope/name@",
    {
      name = "@scope/name";
      spec = VersionSpec.Npm [[SemverVersion.Constraint.ANY]];
    };
    "@scope/name@*",
    {
      name = "@scope/name";
      spec = VersionSpec.Npm [[SemverVersion.Constraint.ANY]];
    };

    "@opam/name",
    {
      name = "@opam/name";
      spec = VersionSpec.Opam [[OpamPackageVersion.Constraint.ANY]];
    };
    "@opam/name@",
    {
      name = "@opam/name";
      spec = VersionSpec.Opam [[OpamPackageVersion.Constraint.ANY]];
    };
    "@opam/name@*",
    {
      name = "@opam/name";
      spec = VersionSpec.Opam [[OpamPackageVersion.Constraint.ANY]];
    };

    "name@git+https://some/repo",
    {
      name = "name";
      spec = VersionSpec.Source (SourceSpec.Git {
        remote = "https://some/repo";
        ref = None;
        manifestFilename = None;
      });
    };
    "name.dot@git+https://some/repo",
    {
      name = "name.dot";
      spec = VersionSpec.Source (SourceSpec.Git {
        remote = "https://some/repo";
        ref = None;
        manifestFilename = None;
      });
    };
    "name-dash@git+https://some/repo",
    {
      name = "name-dash";
      spec = VersionSpec.Source (SourceSpec.Git {
        remote = "https://some/repo";
        ref = None;
        manifestFilename = None;
      });
    };
    "name_underscore@git+https://some/repo",
    {
      name = "name_underscore";
      spec = VersionSpec.Source (SourceSpec.Git {
        remote = "https://some/repo";
        ref = None;
        manifestFilename = None;
      });
    };
    "@opam/name@git+https://some/repo",
    {
      name = "@opam/name";
      spec = VersionSpec.Source (SourceSpec.Git {
        remote = "https://some/repo";
        ref = None;
        manifestFilename = None;
      });
    };
    "@scope/name@git+https://some/repo",
    {
      name = "@scope/name";
      spec = VersionSpec.Source (SourceSpec.Git {
        remote = "https://some/repo";
        ref = None;
        manifestFilename = None;
      });
    };
    "@scope-dash/name@git+https://some/repo",
    {
      name = "@scope-dash/name";
      spec = VersionSpec.Source (SourceSpec.Git {
        remote = "https://some/repo";
        ref = None;
        manifestFilename = None;
      });
    };
    "@scope.dot/name@git+https://some/repo",
    {
      name = "@scope.dot/name";
      spec = VersionSpec.Source (SourceSpec.Git {
        remote = "https://some/repo";
        ref = None;
        manifestFilename = None;
      });
    };
    "@scope_underscore/name@git+https://some/repo",
    {
      name = "@scope_underscore/name";
      spec = VersionSpec.Source (SourceSpec.Git {
        remote = "https://some/repo";
        ref = None;
        manifestFilename = None;
      });
    };

    "pkg@git://github.com/yarnpkg/example-yarn-package.git",
    {
      name = "pkg";
      spec = VersionSpec.Source (SourceSpec.Git {
        remote = "git://github.com/yarnpkg/example-yarn-package.git";
        ref = None;
        manifestFilename = None;
      });
    };

    "pkg@git+https://some/repo",
    {
      name = "pkg";
      spec = VersionSpec.Source (SourceSpec.Git {
        remote = "https://some/repo";
        ref = None;
        manifestFilename = None;
      });
    };

    "pkg@git+https://some/repo#ref",
    {
      name = "pkg";
      spec = VersionSpec.Source (SourceSpec.Git {
        remote = "https://some/repo";
        ref = Some "ref";
        manifestFilename = None;
      });
    };

    "pkg@https://some/url#abc123",
    {
      name = "pkg";
      spec = VersionSpec.Source (SourceSpec.Archive {
        url = "https://some/url";
        checksum = Some (Checksum.Sha1, "abc123");
      });
    };

    "pkg@http://some/url#abc123",
    {
      name = "pkg";
      spec = VersionSpec.Source (SourceSpec.Archive {
        url = "http://some/url";
        checksum = Some (Checksum.Sha1, "abc123");
      });
    };

    "pkg@http://some/url#sha1:abc123",
    {
      name = "pkg";
      spec = VersionSpec.Source (SourceSpec.Archive {
        url = "http://some/url";
        checksum = Some (Checksum.Sha1, "abc123");
      });
    };

    "pkg@http://some/url#md5:abc123",
    {
      name = "pkg";
      spec = VersionSpec.Source (SourceSpec.Archive {
        url = "http://some/url";
        checksum = Some (Checksum.Md5, "abc123");
      });
    };

    "pkg@file:./some/file",
    {
      name = "pkg";
      spec = VersionSpec.Source (SourceSpec.LocalPath {
        path = Path.v "some/file";
        manifestFilename = None;
      });
    };

    "pkg@link:./some/file",
    {
      name = "pkg";
      spec = VersionSpec.Source (SourceSpec.LocalPathLink {
        path = Path.v "some/file";
        manifestFilename = None;
      });
    };
    "pkg@link:../reason-wall-demo",
    {
      name = "pkg";
      spec = VersionSpec.Source (SourceSpec.LocalPathLink {
        path = Path.v "../reason-wall-demo";
        manifestFilename = None;
      });
    };

    "eslint@git+https://github.com/eslint/eslint.git#9d6223040316456557e0a2383afd96be90d28c5a",
    {
      name = "eslint";
      spec = VersionSpec.Source (
        SourceSpec.Git {
          remote = "https://github.com/eslint/eslint.git";
          ref = Some "9d6223040316456557e0a2383afd96be90d28c5a";
          manifestFilename = None;
        });
    };

    (* npm *)
    "pkg@4.1.0",
    {
      name = "pkg";
      spec = VersionSpec.Npm (SemverVersion.Formula.parseExn "4.1.0");
    };
    "pkg@~4.1.0",
    {
      name = "pkg";
      spec = VersionSpec.Npm (SemverVersion.Formula.parseExn "~4.1.0");
    };
    "pkg@^4.1.0",
    {
      name = "pkg";
      spec = VersionSpec.Npm (SemverVersion.Formula.parseExn "^4.1.0");
    };
    "pkg@npm:>4.1.0",
    {
      name = "pkg";
      spec = VersionSpec.Npm (SemverVersion.Formula.parseExn ">4.1.0");
    };
    "pkg@npm:name@>4.1.0",
    {
      name = "pkg";
      spec = VersionSpec.Npm (SemverVersion.Formula.parseExn ">4.1.0");
    };

    (* npm tags *)
    "pkg@latest",
    {
      name = "pkg";
      spec = VersionSpec.NpmDistTag ("latest", None);
    };
    "pkg@next",
    {
      name = "pkg";
      spec = VersionSpec.NpmDistTag ("next", None);
    };
    "pkg@alpha",
    {
      name = "pkg";
      spec = VersionSpec.NpmDistTag ("alpha", None);
    };
    "pkg@beta",
    {
      name = "pkg";
      spec = VersionSpec.NpmDistTag ("beta", None);
    };
  ]

  let expectParsesTo input e =
    match parse input with
    | Ok req ->
      if equal req e
      then true
      else (
        Format.printf "@[<v>parsing: %s@\n     got: %a@\nexpected: %a@\n@]@\n" input pp req pp e;
        false
      )
    | Error err ->
      Format.printf "@[<v>parsing: %s@\n  error: %s@]@\n" input err;
      false

  let%test "parsing" =
    let f passes (req, e) =
      let thisPasses = expectParsesTo req e in
      passes && thisPasses
    in
    List.fold_left ~f ~init:true cases

end)

let make ~name ~spec =
  {name; spec}

module Set = Set.Make(struct
  type nonrec t = t
  let compare = compare
end)

module Map = Map.Make(struct
  type nonrec t = t
  let compare = compare
end)
