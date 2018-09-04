module String = Astring.String

[@@@ocaml.warning "-32"]
type 'a disj = 'a list [@@deriving eq]
[@@@ocaml.warning "-32"]
type 'a conj = 'a list [@@deriving eq]

module AdHocParse : sig
  type 'a t = string -> ('a, string) result

  val (or) : 'a t -> 'a t -> 'a t

  val cut : sep:string -> string -> (string * string, string) result

end = struct
  type 'a t = string -> ('a, string) result

  let (or) a b s =
    match a s with
    | Ok v -> Ok v
    | Error _ -> b s

  let cut ~sep v =
    match String.cut ~sep v with
    | Some (l, r) -> Ok (l, r)
    | None -> Error ("missing " ^ sep)
end

module Source = struct

  type t =
    | Archive of {url : string ; checksum : Checksum.t }
    | Git of {remote : string; commit : string}
    | Github of {user : string; repo : string; commit : string}
    | LocalPath of Path.t
    | LocalPathLink of Path.t
    | NoSource
    [@@deriving (ord, eq)]

  let toString = function
    | Github {user; repo; commit; _} ->
      Printf.sprintf "github:%s/%s#%s" user repo commit
    | Git {remote; commit; _} ->
      Printf.sprintf "git:%s#%s" remote commit
    | Archive {url; checksum} -> "archive:" ^ url ^ "#" ^ (Checksum.show checksum)
    | LocalPath path -> "path:" ^ Path.toString(path)
    | LocalPathLink path -> "link:" ^ Path.toString(path)
    | NoSource -> "no-source:"

  let show = toString

  let parse v =
    let open Result.Syntax in
    match%bind AdHocParse.cut ~sep:":" v with
    | "github", v ->
      let%bind user, v = AdHocParse.cut ~sep:"/" v in
      let%bind repo, commit = AdHocParse.cut ~sep:"#" v in
      return (Github {user; repo; commit})
    | "git", v ->
      let%bind remote, commit = AdHocParse.cut ~sep:"#" v in
      return (Git {remote; commit})
    | "archive", v ->
      let%bind url, checksum = AdHocParse.cut ~sep:"#" v in
      let%bind checksum = Checksum.parse checksum in
      return (Archive {url; checksum})
    | "no-source", "" ->
      return NoSource
    | "path", path ->
      let path = Path.(normalizeAndRemoveEmptySeg (v path)) in
      return (LocalPath path)
    | "link", path ->
      let path = Path.(normalizeAndRemoveEmptySeg (v path)) in
      return (LocalPathLink path)
    | _, _ ->
      let msg = Printf.sprintf "unknown source: %s" v in
      error msg

  let to_yojson v = `String (toString v)

  let of_yojson json =
    let open Result.Syntax in
    let%bind v = Json.Parse.string json in
    parse v

  let pp fmt src =
    Fmt.pf fmt "%s" (toString src)

  module Map = Map.Make(struct
    type nonrec t = t
    let compare = compare
  end)
end

(**
 * A concrete version.
 *)
module Version = struct
  type t =
    | Npm of SemverVersion.Version.t
    | Opam of OpamPackageVersion.Version.t
    | Source of Source.t
    [@@deriving (ord, eq)]

  let toString v =
    match v with
    | Npm t -> SemverVersion.Version.toString(t)
    | Opam v -> "opam:" ^ OpamPackageVersion.Version.toString(v)
    | Source src -> (Source.toString src)

  let show = toString

  let pp fmt v =
    Fmt.fmt "%s" fmt (toString v)

  let parse ?(tryAsOpam=false) v =
    let open Result.Syntax in
    match tryAsOpam, AdHocParse.cut ~sep:":" v with
    | false, Error _ ->
      let%bind v = SemverVersion.Version.parse v in
      return (Npm v)
    | true, Error _ ->
      let%bind v = OpamPackageVersion.Version.parse v in
      return (Opam v)
    | _, Ok ("opam", v) ->
      let%bind v = OpamPackageVersion.Version.parse v in
      return (Opam v)
    | _, Ok _ ->
      let%bind v = Source.parse v in
      return (Source v)

  let parseExn v =
    match parse v with
    | Ok v -> v
    | Error err -> failwith err

  let to_yojson v = `String (toString v)

  let of_yojson json =
    let open Result.Syntax in
    let%bind v = Json.Parse.string json in
    parse v

  let toNpmVersion v =
    match v with
    | Npm v -> SemverVersion.Version.toString(v)
    | Opam t -> OpamPackageVersion.Version.toString(t)
    | Source src -> Source.toString src

  module Map = Map.Make(struct
    type nonrec t = t
    let compare = compare
  end)

end

module Resolutions = struct
  type t = Version.t StringMap.t

  let empty = StringMap.empty

  let find resolutions pkgName =
    StringMap.find_opt pkgName resolutions

  let entries = StringMap.bindings

  let to_yojson v =
    let items =
      let f k v items = (k, (`String (Version.toString v)))::items in
      StringMap.fold f v []
    in
    `Assoc items

  let of_yojson =
    let open Result.Syntax in
    let parseKey k =
      match PackagePath.parse k with
      | Ok ((_path, name)) -> Ok name
      | Error err -> Error err
    in
    let parseValue key =
      function
      | `String v -> begin
        match String.cut ~sep:"/" key with
        | Some ("@opam", _) -> Version.parse ~tryAsOpam:true v
        | _ -> Version.parse v
        end
      | _ -> Error "expected string"
    in
    function
    | `Assoc items ->
      let f res (key, json) =
        let%bind key = parseKey key in
        let%bind value = parseValue key json in
        Ok (StringMap.add key value res)
      in
      Result.List.foldLeft ~f ~init:empty items
    | _ -> Error "expected object"

end


(**
 * This is a spec for a source, which at some point will be resolved to a
 * concrete source Source.t.
 *)
module SourceSpec = struct
  type t =
    | Archive of {url : string; checksum : Checksum.t option;}
    | Git of {remote : string; ref : string option}
    | Github of {user : string; repo : string; ref : string option}
    | LocalPath of Path.t
    | LocalPathLink of Path.t
    | NoSource
    [@@deriving (eq, ord)]

  let toString = function
    | Github {user; repo; ref = None} -> Printf.sprintf "github:%s/%s" user repo
    | Github {user; repo; ref = Some ref} -> Printf.sprintf "github:%s/%s#%s" user repo ref
    | Git {remote; ref = None} -> Printf.sprintf "git:%s" remote
    | Git {remote; ref = Some ref} -> Printf.sprintf "git:%s#%s" remote ref
    | Archive {url; checksum = Some checksum} -> "archive:" ^ url ^ "#" ^ (Checksum.show checksum)
    | Archive {url; checksum = None} -> "archive:" ^ url
    | LocalPath path -> "path:" ^ Path.toString(path)
    | LocalPathLink path -> "link:" ^ Path.toString(path)
    | NoSource -> "no-source:"

  let to_yojson src = `String (toString src)

  let ofSource (source : Source.t) =
    match source with
    | Source.Archive {url; checksum} -> Archive {url; checksum = Some checksum}
    | Source.Git {remote; commit} ->
      Git {remote; ref =  Some commit}
    | Source.Github {user; repo; commit} ->
      Github {user; repo; ref = Some commit}
    | Source.LocalPath p -> LocalPath p
    | Source.LocalPathLink p -> LocalPathLink p
    | Source.NoSource -> NoSource

  let pp fmt spec =
    Fmt.pf fmt "%s" (toString spec)

  let matches ~source spec =
    match spec, source with
    | LocalPath p1, Source.LocalPath p2 ->
      Path.equal p1 p2
    | LocalPath p1, Source.LocalPathLink p2 ->
      Path.equal p1 p2
    | LocalPath _, _ -> false

    | LocalPathLink p1, Source.LocalPathLink p2 ->
      Path.equal p1 p2
    | LocalPathLink _, _ -> false

    | Github ({ref = Some specRef; _} as spec), Source.Github src ->
      String.(
        equal src.user spec.user
        && equal src.repo spec.repo
        && equal src.commit specRef
      )
    | Github ({ref = None; _} as spec), Source.Github src ->
      String.(equal spec.user src.user && equal spec.repo src.repo)
    | Github _, _ -> false

    | Git ({ref = Some specRef; _} as spec), Source.Git src ->
      String.(
        equal spec.remote src.remote
        && equal specRef src.commit
      )
    | Git ({ref = None; _} as spec), Source.Git src ->
      String.(equal spec.remote src.remote)
    | Git _, _ -> false

    | Archive {url = url1; _}, Source.Archive {url = url2; _}  ->
      String.equal url1 url2
    | Archive _, _ -> false

    | NoSource, _ -> false

  module Map = Map.Make(struct
    type nonrec t = t
    let compare = compare
  end)
end

(**
 * This representes a concrete version which at some point will be resolved to a
 * concrete version Version.t.
 *)
module VersionSpec = struct

  type t =
    | Npm of SemverVersion.Formula.DNF.t
    | NpmDistTag of string * SemverVersion.Version.t option
    | Opam of OpamPackageVersion.Formula.DNF.t
    | Source of SourceSpec.t
    [@@deriving (eq, ord)]

  let toString = function
    | Npm formula -> SemverVersion.Formula.DNF.toString formula
    | NpmDistTag (tag, _version) -> tag
    | Opam formula -> OpamPackageVersion.Formula.DNF.toString formula
    | Source src -> SourceSpec.toString src

  let pp fmt spec =
    Fmt.string fmt (toString spec)

  let to_yojson src = `String (toString src)

  let matches ~version spec =
    match spec, version with
    | Npm formula, Version.Npm version ->
      SemverVersion.Formula.DNF.matches ~version formula
    | Npm _, _ -> false

    | NpmDistTag (_tag, Some resolvedVersion), Version.Npm version ->
      SemverVersion.Version.equal resolvedVersion version
    | NpmDistTag (_tag, None), Version.Npm _ -> assert false
    | NpmDistTag (_tag, _), _ -> false

    | Opam formula, Version.Opam version ->
      OpamPackageVersion.Formula.DNF.matches ~version formula
    | Opam _, _ -> false

    | Source srcSpec, Version.Source src ->
      SourceSpec.matches ~source:src srcSpec
    | Source _, _ -> false


  let ofVersion (version : Version.t) =
    match version with
    | Version.Npm v ->
      Npm (SemverVersion.Formula.DNF.unit (SemverVersion.Constraint.EQ v))
    | Version.Opam v ->
      Opam (OpamPackageVersion.Formula.DNF.unit (OpamPackageVersion.Constraint.EQ v))
    | Version.Source src ->
      let srcSpec = SourceSpec.ofSource src in
      Source srcSpec

  module Parse = struct

    let parseRef spec =
      match String.cut ~sep:"#" spec with
      | None -> spec, None
      | Some (spec, "") -> spec, None
      | Some (spec, ref) -> spec, Some ref

    let parseChecksum spec =
      let open Result.Syntax in
      match parseRef spec with
      | spec, None -> return (spec, None)
      | spec, Some checksum ->
        let%bind checksum = Checksum.parse checksum in
        return (spec, Some checksum)

    let github text =

      let normalizeGithubRepo repo =
        match String.cut ~sep:".git" repo with
        | Some (repo, "") -> repo
        | Some _ -> repo
        | None -> repo
      in

      let parts = Str.split (Str.regexp_string "/") text in
      match parts with
      | user::rest::[] ->
        let repo, ref = parseRef rest in
        Ok (Source (SourceSpec.Github {user; repo = normalizeGithubRepo repo; ref}))
      | _ -> Error "not a github source"

    let protoRe =
      let open Re in
      let proto = alt [
        str "file:";
        str "https:";
        str "http:";
        str "git:";
        str "npm:";
        str "link:";
        str "git+";
      ] in
      compile (seq [bos; group proto; group (rep any); eos])

    let parseProto v =
      match Re.exec_opt protoRe v with
      | Some m ->
        let proto = Re.Group.get m 1 in
        let body = Re.Group.get m 2 in
        Some (proto, body)
      | None -> None

    let sourceWithProto v =
      let open Result.Syntax in
      match parseProto v with
      | Some ("link:", path) ->
        let path = Path.(normalizeAndRemoveEmptySeg (v path)) in
        let spec = SourceSpec.LocalPathLink path in
        return (Source spec)
      | Some ("file:", path) ->
        let path = Path.(normalizeAndRemoveEmptySeg (v path)) in
        let spec = SourceSpec.LocalPath path in
        return (Source spec)
      | Some ("https:", _)
      | Some ("http:", _) ->
        let%bind url, checksum = parseChecksum v in
        let spec = SourceSpec.Archive {url; checksum} in
        return (Source spec)
      | Some ("git+", v) ->
        let remote, ref = parseRef v in
        let spec = SourceSpec.Git {remote;ref;} in
        return (Source spec)
      | Some ("git:", _) ->
        let remote, ref = parseRef v in
        let spec = SourceSpec.Git {remote;ref;} in
        return (Source spec)
      | Some ("npm:", v) ->
        begin match String.cut ~rev:true ~sep:"@" v with
        | None ->
          let%bind v = SemverVersion.Formula.parse v in
          return (Npm v)
        | Some (_, v) ->
          let%bind v = SemverVersion.Formula.parse v in
          return (Npm v)
        end
      | Some _
      | None -> Error "unknown proto"

    let path spec =
      if String.is_prefix ~affix:"." spec || String.is_prefix ~affix:"/" spec
      then Ok (Source (SourceSpec.LocalPath (Path.v spec)))
      else Error "not a path"

    let opamConstraint spec =
      match OpamPackageVersion.Formula.parse spec with
      | Ok v -> Ok (Opam v)
      | Error err -> Error err

    let npmDistTag spec =
      let isNpmDistTag v =
        (* npm dist tags can be any strings which cannot be npm version ranges,
          * this is a simplified check for that. *)
        match v.[0] with
        | 'v' -> false
        | '0'..'9' -> false
        | _ -> true
      in
      if isNpmDistTag spec
      then Ok (NpmDistTag (spec, None))
      else Error "not an npm dist-tag"

    let npmAnyConstraint spec =
      Logs.warn (fun m -> m "error parsing version: %s" spec);
      Ok (Npm [[SemverVersion.Constraint.ANY]])

    let npmConstraint spec =
      match SemverVersion.Formula.parse spec with
      | Ok v -> Ok (Npm v)
      | Error err -> Error err

    let opamComplete = AdHocParse.(
      path
      or sourceWithProto
      or github
      or opamConstraint
    )

    let npmComplete = AdHocParse.(
      path
      or sourceWithProto
      or github
      or npmConstraint
      or npmDistTag
      or npmAnyConstraint
    )
  end

  let parseAsNpm = Parse.npmComplete
  let parseAsOpam = Parse.opamComplete

end

module Req = struct
  type t = {
    name: string;
    spec: VersionSpec.t;
  } [@@deriving (eq, ord)]

  module Set = Set.Make(struct
    type nonrec t = t
    let compare = compare
  end)

  let toString {name; spec} =
    name ^ "@" ^ (VersionSpec.toString spec)

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
      parse "name",
      {
        name = "name";
        spec = VersionSpec.Npm [[SemverVersion.Constraint.ANY]];
      };
      parse "name@",
      {
        name = "name";
        spec = VersionSpec.Npm [[SemverVersion.Constraint.ANY]];
      };
      parse "name@*",
      {
        name = "name";
        spec = VersionSpec.Npm [[SemverVersion.Constraint.ANY]];
      };

      parse "@scope/name",
      {
        name = "@scope/name";
        spec = VersionSpec.Npm [[SemverVersion.Constraint.ANY]];
      };
      parse "@scope/name@",
      {
        name = "@scope/name";
        spec = VersionSpec.Npm [[SemverVersion.Constraint.ANY]];
      };
      parse "@scope/name@*",
      {
        name = "@scope/name";
        spec = VersionSpec.Npm [[SemverVersion.Constraint.ANY]];
      };

      parse "@opam/name",
      {
        name = "@opam/name";
        spec = VersionSpec.Opam [[OpamPackageVersion.Constraint.ANY]];
      };
      parse "@opam/name@",
      {
        name = "@opam/name";
        spec = VersionSpec.Opam [[OpamPackageVersion.Constraint.ANY]];
      };
      parse "@opam/name@*",
      {
        name = "@opam/name";
        spec = VersionSpec.Opam [[OpamPackageVersion.Constraint.ANY]];
      };

      parse "name@git+https://some/repo",
      {
        name = "name";
        spec = VersionSpec.Source (SourceSpec.Git {remote = "https://some/repo"; ref = None});
      };
      parse "name.dot@git+https://some/repo",
      {
        name = "name.dot";
        spec = VersionSpec.Source (SourceSpec.Git {remote = "https://some/repo"; ref = None});
      };
      parse "name-dash@git+https://some/repo",
      {
        name = "name-dash";
        spec = VersionSpec.Source (SourceSpec.Git {remote = "https://some/repo"; ref = None});
      };
      parse "name_underscore@git+https://some/repo",
      {
        name = "name_underscore";
        spec = VersionSpec.Source (SourceSpec.Git {remote = "https://some/repo"; ref = None});
      };
      parse "@opam/name@git+https://some/repo",
      {
        name = "@opam/name";
        spec = VersionSpec.Source (SourceSpec.Git {remote = "https://some/repo"; ref = None});
      };
      parse "@scope/name@git+https://some/repo",
      {
        name = "@scope/name";
        spec = VersionSpec.Source (SourceSpec.Git {remote = "https://some/repo"; ref = None});
      };
      parse "@scope-dash/name@git+https://some/repo",
      {
        name = "@scope-dash/name";
        spec = VersionSpec.Source (SourceSpec.Git {remote = "https://some/repo"; ref = None});
      };
      parse "@scope.dot/name@git+https://some/repo",
      {
        name = "@scope.dot/name";
        spec = VersionSpec.Source (SourceSpec.Git {remote = "https://some/repo"; ref = None});
      };
      parse "@scope_underscore/name@git+https://some/repo",
      {
        name = "@scope_underscore/name";
        spec = VersionSpec.Source (SourceSpec.Git {remote = "https://some/repo"; ref = None});
      };

      parse "pkg@git+https://some/repo",
      {
        name = "pkg";
        spec = VersionSpec.Source (SourceSpec.Git {remote = "https://some/repo"; ref = None});
      };

      parse "pkg@git+https://some/repo#ref",
      {
        name = "pkg";
        spec = VersionSpec.Source (SourceSpec.Git {remote = "https://some/repo"; ref = Some "ref"});
      };

      parse "pkg@https://some/url#checksum",
      {
        name = "pkg";
        spec = VersionSpec.Source (SourceSpec.Archive {
          url = "https://some/url";
          checksum = Some (Checksum.Sha1, "checksum");
        });
      };

      parse "pkg@http://some/url#checksum",
      {
        name = "pkg";
        spec = VersionSpec.Source (SourceSpec.Archive {
          url = "http://some/url";
          checksum = Some (Checksum.Sha1, "checksum");
        });
      };

      parse "pkg@http://some/url#sha1:checksum",
      {
        name = "pkg";
        spec = VersionSpec.Source (SourceSpec.Archive {
          url = "http://some/url";
          checksum = Some (Checksum.Sha1, "checksum");
        });
      };

      parse "pkg@http://some/url#md5:checksum",
      {
        name = "pkg";
        spec = VersionSpec.Source (SourceSpec.Archive {
          url = "http://some/url";
          checksum = Some (Checksum.Md5, "checksum");
        });
      };

      parse "pkg@file:./some/file",
      {
        name = "pkg";
        spec = VersionSpec.Source (SourceSpec.LocalPath (Path.v "some/file"));
      };

      parse "pkg@link:./some/file",
      {
        name = "pkg";
        spec = VersionSpec.Source (SourceSpec.LocalPathLink (Path.v "some/file"));
      };
      parse "pkg@link:../reason-wall-demo",
      {
        name = "pkg";
        spec = VersionSpec.Source (SourceSpec.LocalPathLink (Path.v "../reason-wall-demo"));
      };

      parse "eslint@git+https://github.com/eslint/eslint.git#9d6223040316456557e0a2383afd96be90d28c5a",
      {
        name = "eslint";
        spec = VersionSpec.Source (
          SourceSpec.Git {
            remote = "https://github.com/eslint/eslint.git";
            ref = Some "9d6223040316456557e0a2383afd96be90d28c5a"
          });
      };

      (* npm *)
      parse "pkg@4.1.0",
      {
        name = "pkg";
        spec = VersionSpec.Npm (SemverVersion.Formula.parseExn "4.1.0");
      };
      parse "pkg@~4.1.0",
      {
        name = "pkg";
        spec = VersionSpec.Npm (SemverVersion.Formula.parseExn "~4.1.0");
      };
      parse "pkg@^4.1.0",
      {
        name = "pkg";
        spec = VersionSpec.Npm (SemverVersion.Formula.parseExn "^4.1.0");
      };
      parse "pkg@npm:>4.1.0",
      {
        name = "pkg";
        spec = VersionSpec.Npm (SemverVersion.Formula.parseExn ">4.1.0");
      };
      parse "pkg@npm:name@>4.1.0",
      {
        name = "pkg";
        spec = VersionSpec.Npm (SemverVersion.Formula.parseExn ">4.1.0");
      };

      (* npm tags *)
      parse "pkg@latest",
      {
        name = "pkg";
        spec = VersionSpec.NpmDistTag ("latest", None);
      };
      parse "pkg@next",
      {
        name = "pkg";
        spec = VersionSpec.NpmDistTag ("next", None);
      };
      parse "pkg@alpha",
      {
        name = "pkg";
        spec = VersionSpec.NpmDistTag ("alpha", None);
      };
      parse "pkg@beta",
      {
        name = "pkg";
        spec = VersionSpec.NpmDistTag ("beta", None);
      };
    ]

    let expectParsesTo req e =
      match req with
      | Ok req ->
        if equal req e
        then true
        else (
          Format.printf "@[<v>     got: %a@\nexpected: %a@\n@]" pp req pp e;
          false
        )
      | Error err ->
        Format.printf "@[<v>     error: %s@]" err;
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
end

module Dep = struct
  type t = {
    name : string;
    req : req;
  }

  and req =
    | Npm of SemverVersion.Constraint.t
    | NpmDistTag of string
    | Opam of OpamPackageVersion.Constraint.t
    | Source of SourceSpec.t

  let matches ~name ~version dep =
    name = dep.name &&
      match version, dep.req with
      | Version.Npm version, Npm c -> SemverVersion.Constraint.matches ~version c
      | Version.Npm _, _ -> false
      | Version.Opam version, Opam c -> OpamPackageVersion.Constraint.matches ~version c
      | Version.Opam _, _ -> false
      | Version.Source source, Source c -> SourceSpec.matches ~source c
      | Version.Source _, _ -> false

  let pp fmt {name; req;} =
    let ppReq fmt = function
      | Npm c -> SemverVersion.Constraint.pp fmt c
      | NpmDistTag tag -> Fmt.string fmt tag
      | Opam c -> OpamPackageVersion.Constraint.pp fmt c
      | Source src -> SourceSpec.pp fmt src
    in
    Fmt.pf fmt "%s@%a" name ppReq req

end

module NpmDependencies = struct

  type t = Req.t conj [@@deriving eq]

  let empty = []

  let pp fmt deps =
    Fmt.pf fmt "@[<hov>[@;%a@;]@]" (Fmt.list ~sep:(Fmt.unit ", ") Req.pp) deps

  let of_yojson json =
    let open Result.Syntax in
    let%bind items = Json.Parse.assoc json in
    let f deps (name, json) =
      let%bind spec = Json.Parse.string json in
      let%bind req = Req.parse (name ^ "@" ^ spec) in
      return (req::deps)
    in
    Result.List.foldLeft ~f ~init:empty items

  let to_yojson (reqs : t) =
    let items =
      let f (req : Req.t) = (req.name, VersionSpec.to_yojson req.spec) in
      List.map ~f reqs
    in
    `Assoc items

  let toOpamFormula reqs =
    let f reqs (req : Req.t) =
      let update =
        match req.spec with
        | VersionSpec.Npm formula ->
          let f (c : SemverVersion.Constraint.t) =
            {Dep. name = req.name; req = Npm c}
          in
          let formula = SemverVersion.Formula.ofDnfToCnf formula in
          List.map ~f:(List.map ~f) formula
        | VersionSpec.NpmDistTag (tag, _) ->
          [[{Dep. name = req.name; req = NpmDistTag tag}]]
        | VersionSpec.Opam formula ->
          let f (c : OpamPackageVersion.Constraint.t) =
            {Dep. name = req.name; req = Opam c}
          in
          let formula = OpamPackageVersion.Formula.ofDnfToCnf formula in
          List.map ~f:(List.map ~f) formula
        | VersionSpec.Source spec ->
          [[{Dep. name = req.name; req = Source spec}]]
      in
      reqs @ update
    in
    List.fold_left ~f ~init:[] reqs

  let override deps update =
    let map =
      let f map (req : Req.t) = StringMap.add req.name req map in
      let map = StringMap.empty in
      let map = List.fold_left ~f ~init:map deps in
      let map = List.fold_left ~f ~init:map update in
      map
    in
    StringMap.values map

  let find ~name reqs =
    let f (req : Req.t) = req.name = name in
    List.find_opt ~f reqs
end


module Dependencies = struct

  type t =
    | OpamFormula of Dep.t disj conj
    | NpmFormula of Req.t conj

  let toApproximateRequests = function
    | NpmFormula reqs -> reqs
    | OpamFormula reqs ->
      let reqs =
        let f reqs deps =
          let f reqs (dep : Dep.t) =
            let spec =
              match dep.req with
              | Dep.Npm _ -> VersionSpec.Npm [[SemverVersion.Constraint.ANY]]
              | Dep.NpmDistTag tag -> VersionSpec.NpmDistTag (tag, None)
              | Dep.Opam _ -> VersionSpec.Opam [[OpamPackageVersion.Constraint.ANY]]
              | Dep.Source srcSpec -> VersionSpec.Source srcSpec
            in
            Req.Set.add {Req.name = dep.name; spec} reqs
          in
          List.fold_left ~f ~init:reqs deps
        in
        List.fold_left ~f ~init:Req.Set.empty reqs
      in
      Req.Set.elements reqs

  let applyResolutions resolutions (deps : t) =
    match deps with
    | OpamFormula deps ->
      let applyToDep (dep : Dep.t) =
        match Resolutions.find resolutions dep.name with
        | Some version ->
          let req =
            match version with
            | Version.Npm v -> Dep.Npm (SemverVersion.Constraint.EQ v)
            | Version.Opam v -> Dep.Opam (OpamPackageVersion.Constraint.EQ v)
            | Version.Source src -> Dep.Source (SourceSpec.ofSource src)
          in
          {dep with req}
        | None -> dep
      in
      let deps = List.map ~f:(List.map ~f:applyToDep) deps in
      OpamFormula deps
    | NpmFormula reqs ->
      let applyToReq (req : Req.t) =
        match Resolutions.find resolutions req.name with
        | Some version ->
          let spec = VersionSpec.ofVersion version in
          {req with Req. spec}
        | None -> req
      in
      let reqs = List.map ~f:applyToReq reqs in
      NpmFormula reqs

  let pp fmt deps =
    match deps with
    | OpamFormula deps ->
      let ppDisj fmt disj =
        match disj with
        | [] -> Fmt.unit "true" fmt ()
        | [dep] -> Dep.pp fmt dep
        | deps -> Fmt.pf fmt "(%a)" Fmt.(list ~sep:(unit " || ") Dep.pp) deps
      in
      Fmt.pf fmt "@[<h>[@;%a@;]@]" Fmt.(list ~sep:(unit " && ") ppDisj) deps
    | NpmFormula deps -> NpmDependencies.pp fmt deps

  let show deps =
    Format.asprintf "%a" pp deps
end

module ExportedEnv = struct

  [@@@ocaml.warning "-32"]
  type t = item list [@@deriving (show, eq)]

  and item = {
    name : string;
    value : string;
    scope : scope;
  }

  and scope = [ `Global  | `Local ]

  let empty = []

  let scope_to_yojson =
    function
    | `Global -> `String "global"
    | `Local -> `String "local"

  let scope_of_yojson (json : Json.t) =
    let open Result.Syntax in
    match json with
    | `String "global" -> return `Global
    | `String "local" -> return `Local
    | _ -> error "invalid scope value"

  let of_yojson json =
    let open Result.Syntax in
    let f (name, v) =
      match v with
      | `String value -> return { name; value; scope = `Global }
      | `Assoc _ ->
        let%bind value = Json.Parse.field ~name:"val" v in
        let%bind value = Json.Parse.string value in
        let%bind scope = Json.Parse.field ~name:"scope" v in
        let%bind scope = scope_of_yojson scope in
        return { name; value; scope }
      | _ -> error "env value should be a string or an object"
    in
    let%bind items = Json.Parse.assoc json in
    Result.List.map ~f items

  let to_yojson (items : t) =
    let f { name; value; scope } =
      name, `Assoc [
        "val", `String value;
        "scope", scope_to_yojson scope]
    in
    let items = List.map ~f items in
    `Assoc items

end

module File = struct
  [@@@ocaml.warning "-32"]
  type t = {
    name : Path.t;
    content : string;
    (* file, permissions add 0o644 default for backward compat. *)
    perm : (int [@default 0o644]);
  } [@@deriving (yojson, show, eq)]
end

module OpamOverride = struct
  module Opam = struct
    [@@@ocaml.warning "-32"]
    type t = {
      source: (source option [@default None]);
      files: (File.t list [@default []]);
    } [@@deriving (yojson, eq, show)]

    and source = {
      url: string;
      checksum: string;
    }

    let empty = {source = None; files = [];}

  end

  module Command = struct
    [@@@ocaml.warning "-32"]
    type t =
      | Args of string list
      | Line of string
      [@@deriving (eq, show)]

    let of_yojson (json : Json.t) =
      let open Result.Syntax in
      match json with
      | `List _ ->
        let%bind args = Json.Parse.(list string) json in
        return (Args args)
      | `String line -> return (Line line)
      | _ -> error "expected either a list or a string"

    let to_yojson (cmd : t) =
      match cmd with
      | Args args -> `List (List.map ~f:(fun arg -> `String arg) args)
      | Line line -> `String line
  end

  type t = {
    build: (Command.t list option [@default None]);
    install: (Command.t list option [@default None]);
    dependencies: (NpmDependencies.t [@default NpmDependencies.empty]);
    peerDependencies: (NpmDependencies.t [@default NpmDependencies.empty]) ;
    exportedEnv: (ExportedEnv.t [@default ExportedEnv.empty]);
    opam: (Opam.t [@default Opam.empty]);
  } [@@deriving (yojson, eq, show)]

  let empty =
    {
      build = None;
      install = None;
      dependencies = NpmDependencies.empty;
      peerDependencies = NpmDependencies.empty;
      exportedEnv = ExportedEnv.empty;
      opam = Opam.empty;
    }
end

module Opam = struct

  module OpamFile = struct
    type t = OpamFile.OPAM.t
    let pp fmt opam = Fmt.string fmt (OpamFile.OPAM.write_to_string opam)
    let to_yojson opam = `String (OpamFile.OPAM.write_to_string opam)
    let of_yojson = function
      | `String s -> Ok (OpamFile.OPAM.read_from_string s)
      | _ -> Error "expected string"
  end

  module OpamName = struct
    type t = OpamPackage.Name.t
    let pp fmt name = Fmt.string fmt (OpamPackage.Name.to_string name)
    let to_yojson name = `String (OpamPackage.Name.to_string name)
    let of_yojson = function
      | `String name -> Ok (OpamPackage.Name.of_string name)
      | _ -> Error "expected string"
  end

  module OpamPackageVersion = struct
    type t = OpamPackage.Version.t
    let pp fmt name = Fmt.string fmt (OpamPackage.Version.to_string name)
    let to_yojson name = `String (OpamPackage.Version.to_string name)
    let of_yojson = function
      | `String name -> Ok (OpamPackage.Version.of_string name)
      | _ -> Error "expected string"
  end

  type t = {
    name : OpamName.t;
    version : OpamPackageVersion.t;
    opam : OpamFile.t;
    files : unit -> File.t list RunAsync.t;
    override : OpamOverride.t;
  }
  [@@deriving show]
end

type t = {
  name : string;
  version : Version.t;
  originalVersion : Version.t option;
  source : source * source list;
  dependencies: Dependencies.t;
  devDependencies: Dependencies.t;
  opam : Opam.t option;
  kind : kind;
}

and source =
  | Source of Source.t
  | SourceSpec of SourceSpec.t

and kind =
  | Esy
  | Npm

let isOpamPackageName name =
  match String.cut ~sep:"/" name with
  | Some ("@opam", _) -> true
  | _ -> false

let pp fmt pkg =
  Fmt.pf fmt "%s@%a" pkg.name Version.pp pkg.version

let compare pkga pkgb =
  let name = String.compare pkga.name pkgb.name in
  if name = 0
  then Version.compare pkga.version pkgb.version
  else name

module Map = Map.Make(struct
  type nonrec t = t
  let compare = compare
end)

module Set = Set.Make(struct
  type nonrec t = t
  let compare = compare
end)
