module String = Astring.String

[@@@ocaml.warning "-32"]
type 'a disj = 'a list [@@deriving eq]
[@@@ocaml.warning "-32"]
type 'a conj = 'a list [@@deriving eq]

module Parse = struct
  let cutWith sep v =
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

  let parse v =
    let open Result.Syntax in
    match%bind Parse.cutWith ":" v with
    | "github", v ->
      let%bind user, v = Parse.cutWith "/" v in
      let%bind repo, commit = Parse.cutWith "#" v in
      return (Github {user; repo; commit})
    | "git", v ->
      let%bind remote, commit = Parse.cutWith "#" v in
      return (Git {remote; commit})
    | "archive", v ->
      let%bind url, checksum = Parse.cutWith "#" v in
      let%bind checksum = Checksum.parse checksum in
      return (Archive {url; checksum})
    | "no-source", "" ->
      return NoSource
    | "path", p ->
      return (LocalPath (Path.v p))
    | "link", p ->
      return (LocalPathLink (Path.v p))
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
    | Opam of OpamVersion.Version.t
    | Source of Source.t
    [@@deriving (ord, eq)]

  let toString v =
    match v with
    | Npm t -> SemverVersion.Version.toString(t)
    | Opam v -> "opam:" ^ OpamVersion.Version.toString(v)
    | Source src -> (Source.toString src)

  let pp fmt v =
    Fmt.fmt "%s" fmt (toString v)

  let parse v =
    let open Result.Syntax in
    match Parse.cutWith ":" v with
    | Error _ ->
      let%bind v = SemverVersion.Version.parse v in
      return (Npm v)
    | Ok ("opam", v) ->
      let%bind v = OpamVersion.Version.parse v in
      return (Opam v)
    | Ok _ ->
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
    | Opam t -> OpamVersion.Version.toString(t)
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
        match String.cut ~sep:"/" key, String.cut ~sep:":" v with
        | Some ("@opam", _), Some("opam", _) -> Version.parse v
        | Some ("@opam", _), _ -> Version.parse ("opam:" ^ v)
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
    | Opam of OpamVersion.Formula.DNF.t
    | Source of SourceSpec.t
    [@@deriving (eq, ord)]

  let toString = function
    | Npm formula -> SemverVersion.Formula.DNF.toString formula
    | Opam formula -> OpamVersion.Formula.DNF.toString formula
    | Source src -> SourceSpec.toString src

  let pp fmt spec =
    Fmt.string fmt (toString spec)

  let to_yojson src = `String (toString src)

  let matches ~version spec =
    match spec, version with
    | Npm formula, Version.Npm version ->
      SemverVersion.Formula.DNF.matches ~version formula
    | Npm _, _ -> false

    | Opam formula, Version.Opam version ->
      OpamVersion.Formula.DNF.matches ~version formula
    | Opam _, _ -> false

    | Source srcSpec, Version.Source src ->
      SourceSpec.matches ~source:src srcSpec
    | Source _, _ -> false


  let ofVersion (version : Version.t) =
    match version with
    | Version.Npm v ->
      Npm (SemverVersion.Formula.DNF.unit (SemverVersion.Formula.Constraint.EQ v))
    | Version.Opam v ->
      Opam (OpamVersion.Formula.DNF.unit (OpamVersion.Formula.Constraint.EQ v))
    | Version.Source src ->
      let srcSpec = SourceSpec.ofSource src in
      Source srcSpec
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

  let tryParseGitHubSpec text =

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
      Some (SourceSpec.Github {user; repo = normalizeGithubRepo repo; ref})
    | _ -> None

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

  let tryParseProto v =
    let open Result.Syntax in
    match parseProto v with
    | Some ("link:", v) ->
      let spec = SourceSpec.LocalPathLink (Path.v v) in
      return (Some (VersionSpec.Source spec))
    | Some ("file:", v) ->
      let spec = SourceSpec.LocalPath (Path.v v) in
      return (Some (VersionSpec.Source spec))
    | Some ("https:", _)
    | Some ("http:", _) ->
      let%bind url, checksum = parseChecksum v in
      let spec = SourceSpec.Archive {url; checksum} in
      return (Some (VersionSpec.Source spec))
    | Some ("git+", v) ->
      let remote, ref = parseRef v in
      let spec = SourceSpec.Git {remote;ref;} in
      return (Some (VersionSpec.Source spec))
    | Some ("git:", _) ->
      let remote, ref = parseRef v in
      let spec = SourceSpec.Git {remote;ref;} in
      return (Some (VersionSpec.Source spec))
    | Some ("npm:", v) ->
      begin match String.cut ~rev:true ~sep:"@" v with
      | None ->
        let%bind v = SemverVersion.Formula.parse v in
        return (Some (VersionSpec.Npm v))
      | Some (_, v) ->
        let%bind v = SemverVersion.Formula.parse v in
        return (Some (VersionSpec.Npm v))
      end
    | Some _
    | None ->
      begin match tryParseGitHubSpec v with
      | Some spec -> return (Some (VersionSpec.Source spec))
      | None -> return None
      end

  let make ~name ~spec =
    let open Result.Syntax in
    if String.is_prefix ~affix:"." spec || String.is_prefix ~affix:"/" spec
    then
      let spec = VersionSpec.Source (SourceSpec.LocalPath (Path.v spec)) in
      Ok {name; spec}
    else
      let%bind spec =
        match String.cut ~sep:"/" name with
        | Some ("@opam", _opamName) -> begin
          match%bind tryParseProto spec with
          | Some v -> Ok v
          | None -> Ok (VersionSpec.Opam (OpamVersion.Formula.parse spec))
          end
        | Some _
        | None -> begin
          match%bind tryParseProto spec with
          | Some v -> Ok v
          | None ->
            begin match SemverVersion.Formula.parse spec with
              | Ok v -> Ok (VersionSpec.Npm v)
              | Error _ ->
                Logs.warn (fun m -> m "error parsing version: %s" spec);
                Ok (VersionSpec.Npm [[SemverVersion.Constraint.ANY]])
            end
          end
      in
      Ok {name; spec;}

  let%test_module "parsing" = (module struct

    let cases = [
      make ~name:"pkg" ~spec:"git+https://some/repo",
      VersionSpec.Source (SourceSpec.Git {remote = "https://some/repo"; ref = None});

      make ~name:"pkg" ~spec:"git://github.com/caolan/async.git",
      VersionSpec.Source (SourceSpec.Git {
        remote = "git://github.com/caolan/async.git";
        ref = None
      });

      make ~name:"pkg" ~spec:"git+https://some/repo#ref",
      VersionSpec.Source (SourceSpec.Git {remote = "https://some/repo"; ref = Some "ref"});

      make ~name:"pkg" ~spec:"https://some/url#checksum",
      VersionSpec.Source (SourceSpec.Archive {
        url = "https://some/url";
        checksum = Some (Checksum.Sha1, "checksum");
      });

      make ~name:"pkg" ~spec:"http://some/url#checksum",
      VersionSpec.Source (SourceSpec.Archive {
        url = "http://some/url";
        checksum = Some (Checksum.Sha1, "checksum");
      });

      make ~name:"pkg" ~spec:"http://some/url#sha1:checksum",
      VersionSpec.Source (SourceSpec.Archive {
        url = "http://some/url";
        checksum = Some (Checksum.Sha1, "checksum");
      });

      make ~name:"pkg" ~spec:"http://some/url#md5:checksum",
      VersionSpec.Source (SourceSpec.Archive {
        url = "http://some/url";
        checksum = Some (Checksum.Md5, "checksum");
      });

      make ~name:"pkg" ~spec:"file:./some/file",
      VersionSpec.Source (SourceSpec.LocalPath (Path.v "./some/file"));

      make ~name:"pkg" ~spec:"link:./some/file",
      VersionSpec.Source (SourceSpec.LocalPathLink (Path.v "./some/file"));
      make ~name:"pkg" ~spec:"link:../reason-wall-demo",
      VersionSpec.Source (SourceSpec.LocalPathLink (Path.v "../reason-wall-demo"));

      make
        ~name:"eslint"
        ~spec:"git+https://github.com/eslint/eslint.git#9d6223040316456557e0a2383afd96be90d28c5a",
      VersionSpec.Source (
        SourceSpec.Git {
          remote = "https://github.com/eslint/eslint.git";
          ref = Some "9d6223040316456557e0a2383afd96be90d28c5a"
        });

      (* npm *)
      make ~name:"pkg" ~spec:"4.1.0",
      VersionSpec.Npm (SemverVersion.Formula.parseExn "4.1.0");
      make ~name:"pkg" ~spec:"~4.1.0",
      VersionSpec.Npm (SemverVersion.Formula.parseExn "~4.1.0");
      make ~name:"pkg" ~spec:"^4.1.0",
      VersionSpec.Npm (SemverVersion.Formula.parseExn "^4.1.0");
      make ~name:"pkg" ~spec:"npm:>4.1.0",
      VersionSpec.Npm (SemverVersion.Formula.parseExn ">4.1.0");
      make ~name:"pkg" ~spec:"npm:name@>4.1.0",
      VersionSpec.Npm (SemverVersion.Formula.parseExn ">4.1.0");
    ]

    let expectParsesTo req e =
      match req with
      | Ok req ->
        if VersionSpec.equal req.spec e
        then true
        else (
          Format.printf "@[<v>     got: %a@\nexpected: %a@\n@]"
            VersionSpec.pp req.spec VersionSpec.pp e;
          false
        )
      | Error err ->
        Format.printf "@[<v>     error: %s@]" err;
        false

    let%test "parsing" =
      let f passes (req, e) =
        passes && (expectParsesTo req e)
      in
      List.fold_left ~f ~init:true cases

  end)


  let ofSpec ~name ~spec =
    {name; spec}

  let name req = req.name
  let spec req = req.spec
end

module Dep = struct
  type t = {
    name : string;
    req : req;
  }

  and req =
    | Npm of SemverVersion.Formula.Constraint.t
    | Opam of OpamVersion.Formula.Constraint.t
    | Source of SourceSpec.t

  let matches ~name ~version dep =
    name = dep.name &&
      match version, dep.req with
      | Version.Npm version, Npm c -> SemverVersion.Constraint.matches ~version c
      | Version.Npm _, _ -> false
      | Version.Opam version, Opam c -> OpamVersion.Constraint.matches ~version c
      | Version.Opam _, _ -> false
      | Version.Source source, Source c -> SourceSpec.matches ~source c
      | Version.Source _, _ -> false

  let pp fmt {name; req;} =
    let ppReq fmt = function
      | Npm c -> SemverVersion.Formula.Constraint.pp fmt c
      | Opam c -> OpamVersion.Formula.Constraint.pp fmt c
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
      let%bind req = Req.make ~name ~spec in
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
        | VersionSpec.Opam formula ->
          let f (c : OpamVersion.Constraint.t) =
            {Dep. name = req.name; req = Opam c}
          in
          let formula = OpamVersion.Formula.ofDnfToCnf formula in
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
              | Dep.Opam _ -> VersionSpec.Opam [[OpamVersion.Constraint.ANY]]
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
            | Version.Opam v -> Dep.Opam (OpamVersion.Constraint.EQ v)
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

  module OpamVersion = struct
    type t = OpamPackage.Version.t
    let pp fmt name = Fmt.string fmt (OpamPackage.Version.to_string name)
    let to_yojson name = `String (OpamPackage.Version.to_string name)
    let of_yojson = function
      | `String name -> Ok (OpamPackage.Version.of_string name)
      | _ -> Error "expected string"
  end

  type t = {
    name : OpamName.t;
    version : OpamVersion.t;
    opam : OpamFile.t;
    files : unit -> File.t list RunAsync.t;
    override : OpamOverride.t;
  }
  [@@deriving show]
end

type t = {
  name : string;
  version : Version.t;
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
