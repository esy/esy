include Metadata.Req

let show {name; spec} =
  name ^ "@" ^ (VersionSpec.show spec)

let to_yojson req =
  `String (show req)

let pp fmt req =
  Fmt.fmt "%s" fmt (show req)

let matches ~name ~version req =
  name = req.name && VersionSpec.matches ~version req.spec

module Parse = struct
  include Parse

  let name = take_while1 (function
    | '@' | '/' -> false
    | _ -> true
  )
  let opamPackageName =
    let make scope name = `opam (scope ^ name) in
    make <$> (string "@opam/") <*> name

  let npmPackageNameWithScope =
    let make scope name = `npm ("@" ^ scope ^ "/" ^ name) in
    make <$> char '@' *> name <*> char '/' *> name

  let npmPackageName =
    let make name = `npm name in
    make <$> name

  let packageName =
    opamPackageName <|> npmPackageNameWithScope <|> npmPackageName

  let parser =
    let%bind name = packageName in
    match%bind peek_char with
    | None ->
      let name, spec =
        match name with
        | `npm name -> name, VersionSpec.Npm [[SemverVersion.Constraint.ANY]]
        | `opam name -> name, VersionSpec.Opam [[OpamPackageVersion.Constraint.ANY]]
      in
      return {name; spec};
    | Some '@' ->
      let%bind () = advance 1 in
      let%bind nextChar = peek_char in
      begin match nextChar, name with
      | None, _ ->
        let name, spec =
          match name with
          | `npm name -> name, VersionSpec.Npm [[SemverVersion.Constraint.ANY]]
          | `opam name -> name, VersionSpec.Opam [[OpamPackageVersion.Constraint.ANY]]
        in
        return {name; spec};
      | Some _, `opam name ->
        let%bind spec = VersionSpec.parserOpam in
        return {name; spec};
      | Some _, `npm name ->
        let%bind spec = VersionSpec.parserNpm in
        return {name; spec};
      end
    | _ -> fail "cannot parse request"
end

let parse =
  Parse.(parse parser)

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
      spec = VersionSpec.Source (Orig (SourceSpec.Git {
        remote = "https://some/repo";
        ref = None;
        manifest = None;
      }));
    };
    "name.dot@git+https://some/repo",
    {
      name = "name.dot";
      spec = VersionSpec.Source (Orig (SourceSpec.Git {
        remote = "https://some/repo";
        ref = None;
        manifest = None;
      }));
    };
    "name-dash@git+https://some/repo",
    {
      name = "name-dash";
      spec = VersionSpec.Source (Orig (SourceSpec.Git {
        remote = "https://some/repo";
        ref = None;
        manifest = None;
      }));
    };
    "name_underscore@git+https://some/repo",
    {
      name = "name_underscore";
      spec = VersionSpec.Source (Orig (SourceSpec.Git {
        remote = "https://some/repo";
        ref = None;
        manifest = None;
      }));
    };
    "@opam/name@git+https://some/repo",
    {
      name = "@opam/name";
      spec = VersionSpec.Source (Orig (SourceSpec.Git {
        remote = "https://some/repo";
        ref = None;
        manifest = None;
      }));
    };
    "@scope/name@git+https://some/repo",
    {
      name = "@scope/name";
      spec = VersionSpec.Source (Orig (SourceSpec.Git {
        remote = "https://some/repo";
        ref = None;
        manifest = None;
      }));
    };
    "@scope-dash/name@git+https://some/repo",
    {
      name = "@scope-dash/name";
      spec = VersionSpec.Source (Orig (SourceSpec.Git {
        remote = "https://some/repo";
        ref = None;
        manifest = None;
      }));
    };
    "@scope.dot/name@git+https://some/repo",
    {
      name = "@scope.dot/name";
      spec = VersionSpec.Source (Orig (SourceSpec.Git {
        remote = "https://some/repo";
        ref = None;
        manifest = None;
      }));
    };
    "@scope_underscore/name@git+https://some/repo",
    {
      name = "@scope_underscore/name";
      spec = VersionSpec.Source (Orig (SourceSpec.Git {
        remote = "https://some/repo";
        ref = None;
        manifest = None;
      }));
    };

    "pkg@git://github.com/yarnpkg/example-yarn-package.git",
    {
      name = "pkg";
      spec = VersionSpec.Source (Orig (SourceSpec.Git {
        remote = "git://github.com/yarnpkg/example-yarn-package.git";
        ref = None;
        manifest = None;
      }));
    };

    "pkg@git+https://some/repo",
    {
      name = "pkg";
      spec = VersionSpec.Source (Orig (SourceSpec.Git {
        remote = "https://some/repo";
        ref = None;
        manifest = None;
      }));
    };

    "pkg@git+https://some/repo#ref",
    {
      name = "pkg";
      spec = VersionSpec.Source (Orig (SourceSpec.Git {
        remote = "https://some/repo";
        ref = Some "ref";
        manifest = None;
      }));
    };

    "pkg@https://some/url#abc123",
    {
      name = "pkg";
      spec = VersionSpec.Source (Orig (SourceSpec.Archive {
        url = "https://some/url";
        checksum = Some (Checksum.Sha1, "abc123");
      }));
    };

    "pkg@http://some/url#abc123",
    {
      name = "pkg";
      spec = VersionSpec.Source (Orig (SourceSpec.Archive {
        url = "http://some/url";
        checksum = Some (Checksum.Sha1, "abc123");
      }));
    };

    "pkg@http://some/url#sha1:abc123",
    {
      name = "pkg";
      spec = VersionSpec.Source (Orig (SourceSpec.Archive {
        url = "http://some/url";
        checksum = Some (Checksum.Sha1, "abc123");
      }));
    };

    "pkg@http://some/url#md5:abc123",
    {
      name = "pkg";
      spec = VersionSpec.Source (Orig (SourceSpec.Archive {
        url = "http://some/url";
        checksum = Some (Checksum.Md5, "abc123");
      }));
    };

    "pkg@file:./some/file",
    {
      name = "pkg";
      spec = VersionSpec.Source (Orig (SourceSpec.LocalPath {
        path = Path.v "some/file";
        manifest = None;
      }));
    };

    "pkg@link:./some/file",
    {
      name = "pkg";
      spec = VersionSpec.Source (Orig (SourceSpec.LocalPathLink {
        path = Path.v "some/file";
        manifest = None;
      }));
    };
    "pkg@link:../reason-wall-demo",
    {
      name = "pkg";
      spec = VersionSpec.Source (Orig (SourceSpec.LocalPathLink {
        path = Path.v "../reason-wall-demo";
        manifest = None;
      }));
    };

    "eslint@git+https://github.com/eslint/eslint.git#9d6223040316456557e0a2383afd96be90d28c5a",
    {
      name = "eslint";
      spec = VersionSpec.Source (
        Orig (SourceSpec.Git {
          remote = "https://github.com/eslint/eslint.git";
          ref = Some "9d6223040316456557e0a2383afd96be90d28c5a";
          manifest = None;
        }));
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
