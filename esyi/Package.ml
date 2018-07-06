module String = Astring.String

type 'a disj = 'a list
type 'a conj = 'a list

module Parse = struct
  let cutWith sep v =
    match String.cut ~sep v with
    | Some (l, r) -> Ok (l, r)
    | None -> Error ("missing " ^ sep)
end

module Source = struct

  type t =
    | Archive of string * string
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
    | Archive (url, checksum) -> "archive:" ^ url ^ "#" ^ checksum
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
      return (Archive (url, checksum))
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

(**
 * This is a spec for a source, which at some point will be resolved to a
 * concrete source Source.t.
 *)
module SourceSpec = struct
  type t =
    | Archive of string * string option
    | Git of {remote : string; ref : string option}
    | Github of {user : string; repo : string; ref : string option}
    | LocalPath of Path.t
    | LocalPathLink of Path.t
    | NoSource
    [@@deriving eq]

  let toString = function
    | Github {user; repo; ref = None} -> Printf.sprintf "github:%s/%s" user repo
    | Github {user; repo; ref = Some ref} -> Printf.sprintf "github:%s/%s#%s" user repo ref
    | Git {remote; ref = None} -> Printf.sprintf "git:%s" remote
    | Git {remote; ref = Some ref} -> Printf.sprintf "git:%s#%s" remote ref
    | Archive (url, Some checksum) -> "archive:" ^ url ^ "#" ^ checksum
    | Archive (url, None) -> "archive:" ^ url
    | LocalPath path -> "path:" ^ Path.toString(path)
    | LocalPathLink path -> "link:" ^ Path.toString(path)
    | NoSource -> "no-source:"

  let to_yojson src = `String (toString src)

  let ofSource (source : Source.t) =
    match source with
    | Source.Archive (url, checksum) -> Archive (url, Some checksum)
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

    | Archive (url1, _), Source.Archive (url2, _)  ->
      String.equal url1 url2
    | Archive _, _ -> false

    | NoSource, _ -> false
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
    [@@deriving eq]

  let toString = function
    | Npm formula -> SemverVersion.Formula.DNF.toString formula
    | Opam formula -> "opam:" ^ OpamVersion.Formula.DNF.toString formula
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
  }

  let toString {name; spec} =
    name ^ "@" ^ (VersionSpec.toString spec)

  let to_yojson req =
    `String (toString req)

  let pp fmt req =
    Fmt.fmt "%s" fmt (toString req)

  let parseRef spec =
    match String.cut ~sep:"#" spec with
    | None -> spec, None
    | Some (spec, "") -> spec, None
    | Some (spec, ref) -> spec, Some ref

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

  let tryParseSourceSpec v =
    match parseProto v with
    | Some ("link:", v) -> Some (SourceSpec.LocalPathLink (Path.v v))
    | Some ("file:", v) -> Some (SourceSpec.LocalPath (Path.v v))
    | Some ("https:", _)
    | Some ("http:", _) ->
      let url, checksum = parseRef v in
      Some (SourceSpec.Archive (url, checksum))
    | Some ("git+", v) ->
      let remote, ref = parseRef v in
      Some (SourceSpec.Git {remote;ref;})
    | Some ("git:", _) ->
      let remote, ref = parseRef v in
      Some (SourceSpec.Git {remote;ref;})
    | Some _
    | None -> tryParseGitHubSpec v

  let make ~name ~spec =
    if String.is_prefix ~affix:"." spec || String.is_prefix ~affix:"/" spec
    then
      let spec = VersionSpec.Source (SourceSpec.LocalPath (Path.v spec)) in
      {name; spec}
    else
      let spec =
        match String.cut ~sep:"/" name with
        | Some ("@opam", _opamName) -> begin
          match tryParseSourceSpec spec with
          | Some spec -> VersionSpec.Source spec
          | None -> VersionSpec.Opam (OpamVersion.Formula.parse spec)
          end
        | Some _
        | None -> begin
          match tryParseSourceSpec spec with
          | Some spec -> VersionSpec.Source spec
          | None ->
            begin match SemverVersion.Formula.parse spec with
              | Ok v -> VersionSpec.Npm v
              | Error err ->
                Logs.warn (fun m ->
                  m "invalid version spec %s treating as *:@\n  %s" spec err);
                VersionSpec.Npm SemverVersion.Formula.any
            end
          end
      in
      {name; spec;}

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
      VersionSpec.Source (SourceSpec.Archive ("https://some/url", Some "checksum"));

      make ~name:"pkg" ~spec:"http://some/url#checksum",
      VersionSpec.Source (SourceSpec.Archive ("http://some/url", Some "checksum"));

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
    ]

    let expectParsesTo req e =
      if VersionSpec.equal req.spec e
      then true
      else (
        Format.printf "@[<v>     got: %a@\nexpected: %a@\n@]"
          VersionSpec.pp req.spec VersionSpec.pp e;
        false
      )

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

module DepFormula = struct
  type t =
    | Npm of SemverVersion.Formula.CNF.t
    | Opam of OpamVersion.Formula.CNF.t
    | Source of SourceSpec.t

  let matches ~version formula =
    match version, formula with
    | Version.Npm version, Npm formula ->
      SemverVersion.Formula.CNF.matches ~version formula
    | Version.Npm _, _ -> false

    | Version.Opam version, Opam formula ->
      OpamVersion.Formula.CNF.matches ~version formula
    | Version.Opam _, _ -> false

    | Version.Source source, Source sourceSpec ->
      SourceSpec.matches ~source sourceSpec
    | Version.Source _, _ -> false

  let pp fmt = function
    | Npm f -> SemverVersion.Formula.CNF.pp fmt f
    | Opam f -> OpamVersion.Formula.CNF.pp fmt f
    | Source srcSpec -> SourceSpec.pp fmt srcSpec

end

module Dependencies = struct

  type t = Dep.t disj conj

  let empty = []

  let mapDeps ~f formula =
    List.map ~f:(List.map ~f) formula

  let filterDeps ~f formula =
    let f formula disj =
      match List.filter ~f disj with
      | [] -> formula
      | disj -> disj::formula
    in
    List.fold_left ~f ~init:[] formula

  let override ~dep formula =
    let f (edep : Dep.t) =
      if edep.name = dep.Dep.name
      then dep
      else edep
    in
    mapDeps ~f formula

  let overrideMany ~deps formula =
    let f deps dep = override ~dep deps in
    List.fold_left ~f ~init:formula deps

  let subformulaForPackage ~name:forName formula =
    let f {Dep.name; _} = name = forName in
    match filterDeps ~f formula with
    | [] -> None
    | formula -> Some formula

  let describeByPackageName (formula : t) =
    let desc =
      let f desc disj =
        let up =
          let f byName {Dep. name; req} =
            match StringMap.find_opt name byName, req with
            | Some (npm, opam, source), Dep.Npm c ->
              StringMap.add name (c::npm, opam, source) byName
            | Some (npm, opam, source), Dep.Opam c ->
              StringMap.add name (npm, c::opam, source) byName
            | Some (npm, opam, source), Dep.Source c ->
              StringMap.add name (npm, opam, c::source) byName
            | None, Dep.Npm c ->
              StringMap.add name ([c], [], []) byName
            | None, Dep.Opam c ->
              StringMap.add name ([], [c], []) byName
            | None, Dep.Source c ->
              StringMap.add name ([], [], [c]) byName
          in
          List.fold_left ~f ~init:StringMap.empty disj
        in
        let merge _k a b =
          match a, b with
          | None, None -> None
          | Some a, None -> Some a
          | None, Some (npmu, opamu, sourceu) ->
            let npm = match npmu with | [] -> [] | f -> [f] in
            let opam = match opamu with | [] -> [] | f -> [f] in
            Some (npm, opam, sourceu)
          | Some (npm, opam, source), Some (npmu, opamu, sourceu) ->
            let npm = match npmu with | [] -> npm | f -> f::npm in
            let opam = match opamu with | [] -> opam | f -> f::opam in
            Some (npm, opam, sourceu @ source)
        in
        StringMap.merge merge desc up
      in
      List.fold_left ~f ~init:StringMap.empty formula
    in
    let f name (npm, opam, sources) formulas =
      let formulas =
        List.fold_left
          ~f:(fun formulas source -> (name, DepFormula.Source source)::formulas)
          ~init:formulas sources
      in
      let formulas =
        match npm with
        | [] -> formulas
        | f -> (name, DepFormula.Npm f)::formulas
      in
      let formulas =
        match opam with
        | [] -> formulas
        | f -> (name, DepFormula.Opam f)::formulas
      in
      formulas
    in
    StringMap.fold f desc []

  let pp fmt deps =
    let ppDisj fmt disj =
      match disj with
      | [] -> Fmt.unit "true" fmt ()
      | [dep] -> Dep.pp fmt dep
      | deps -> Fmt.pf fmt "(%a)" Fmt.(list ~sep:(unit " || ") Dep.pp) deps
    in
    Fmt.pf fmt "@[<h>[@;%a@;]@]" Fmt.(list ~sep:(unit " && ") ppDisj) deps

  let show deps =
    Format.asprintf "%a" pp deps
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

  let apply resolutions (dep : Dep.t) =
    match find resolutions dep.name with
    | Some version ->
      let req =
        match version with
        | Version.Npm v -> Dep.Npm (SemverVersion.Constraint.EQ v)
        | Version.Opam v -> Dep.Opam (OpamVersion.Constraint.EQ v)
        | Version.Source src -> Dep.Source (SourceSpec.ofSource src)
      in
      Some {dep with req}
    | None -> None

end

module ExportedEnv = struct
  type t = item list

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
    content : string
  } [@@deriving (yojson, show)]
end

module OpamInfo = struct
  type t = {
    manifest : Json.t;
    files : unit -> File.t list RunAsync.t;
  }
  [@@deriving show]
end

type t = {
  name : string;
  version : Version.t;
  source : source;
  dependencies: Dependencies.t;
  devDependencies: Dependencies.t;
  opam : OpamInfo.t option;
  kind : kind;
}

and source =
  | Source of Source.t
  | SourceSpec of SourceSpec.t

and kind =
  | Esy
  | Npm

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
