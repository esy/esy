module String = Astring.String

[@@@ocaml.warning "-32"]
type 'a disj = 'a list [@@deriving eq]
[@@@ocaml.warning "-32"]
type 'a conj = 'a list [@@deriving eq]

module Source = Source
module Version = Version

module SourceSpec = SourceSpec
module VersionSpec = VersionSpec

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
