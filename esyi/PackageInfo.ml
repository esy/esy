module String = Astring.String

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
    | NoSource
    [@@deriving (ord, eq)]


  let toString = function
    | Github {user; repo; commit; _} ->
      Printf.sprintf "github:%s/%s#%s" user repo commit
    | Git {remote; commit; _} ->
      Printf.sprintf "git:%s#%s" remote commit
    | Archive (url, checksum) -> "archive:" ^ url ^ "#" ^ checksum
    | LocalPath path -> "path:" ^ Path.toString(path)
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
    | Npm of NpmVersion.Version.t
    | Opam of OpamVersion.Version.t
    | Source of Source.t
    [@@deriving (ord, eq)]

  let toString v =
    match v with
    | Npm t -> NpmVersion.Version.toString(t)
    | Opam v -> "opam:" ^ OpamVersion.Version.toString(v)
    | Source src -> (Source.toString src)

  let pp fmt v =
    Fmt.fmt "%s" fmt (toString v)

  let parse v =
    let open Result.Syntax in
    match Parse.cutWith ":" v with
    | Error _ ->
      let%bind v = NpmVersion.Version.parse v in
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
    | Npm v -> NpmVersion.Version.toString(v)
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
    | NoSource

  let toString = function
    | Github {user; repo; ref = None} -> Printf.sprintf "github:%s/%s" user repo
    | Github {user; repo; ref = Some ref} -> Printf.sprintf "github:%s/%s#%s" user repo ref
    | Git {remote; ref = None} -> Printf.sprintf "git:%s" remote
    | Git {remote; ref = Some ref} -> Printf.sprintf "git:%s#%s" remote ref
    | Archive (url, Some checksum) -> "archive:" ^ url ^ "#" ^ checksum
    | Archive (url, None) -> "archive:" ^ url
    | LocalPath path -> "path:" ^ Path.toString(path)
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
    | Source.NoSource -> NoSource

  let pp fmt spec =
    Fmt.pf fmt "%s" (toString spec)
end

(**
 * This representes a concrete version which at some point will be resolved to a
 * concrete version Version.t.
 *)
module VersionSpec = struct

  type t =
    | Npm of NpmVersion.Formula.DNF.t
    | Opam of OpamVersion.Formula.DNF.t
    | Source of SourceSpec.t

  let toString = function
    | Npm formula -> NpmVersion.Formula.DNF.toString formula
    | Opam formula -> "opam:" ^ OpamVersion.Formula.DNF.toString formula
    | Source src -> SourceSpec.toString src

  let to_yojson src = `String (toString src)

  let matches ~version spec =
    match spec, version with
    | Npm formula, Version.Npm version ->
      NpmVersion.Formula.DNF.matches ~version formula
    | Opam formula, Version.Opam version ->
      OpamVersion.Formula.DNF.matches ~version formula
    | Source (SourceSpec.LocalPath p1), Version.Source (Source.LocalPath p2) ->
      Path.equal p1 p2

    | Source (SourceSpec.Github ({ref = Some specRef; _} as spec)),
      Version.Source (Source.Github src) ->
      String.(
        equal src.user spec.user
        && equal src.repo spec.repo
        && equal src.commit specRef
      )
    | Source (SourceSpec.Github ({ref = None; _} as spec)),
      Version.Source (Source.Github src) ->
      String.(equal spec.user src.user && equal spec.repo src.repo)

    | Source (SourceSpec.Git ({ref = Some specRef; _} as spec)),
      Version.Source (Source.Git src) ->
      String.(
        equal spec.remote src.remote
        && equal specRef src.commit
      )
    | Source (SourceSpec.Git ({ref = None; _} as spec)),
      Version.Source (Source.Git src) ->
      String.(equal spec.remote src.remote)

    | _ -> false

  let ofVersion (version : Version.t) =
    match version with
    | Version.Npm v ->
      Npm (NpmVersion.Formula.DNF.unit (NpmVersion.Formula.Constraint.EQ v))
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

  let make ~name ~spec =

    let parseRef spec =
      match String.cut ~sep:"#" spec with
      | None -> spec, None
      | Some (spec, "") -> spec, None
      | Some (spec, ref) -> spec, Some ref
    in

    let parseGitHubSpec text =

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
    in

    if String.is_prefix ~affix:"." spec || String.is_prefix ~affix:"/" spec
    then
      let spec = VersionSpec.Source (SourceSpec.LocalPath (Path.v spec)) in
      {name; spec}
    else
      match String.cut ~sep:"/" name with
      | Some ("@opam", _opamName) ->
        let spec =
          match parseGitHubSpec spec with
          | Some gh -> VersionSpec.Source gh
          | None -> VersionSpec.Opam (OpamVersion.Formula.parse spec)
        in {name; spec;}
      | Some _
      | None ->
        let spec =
          match parseGitHubSpec spec with
            | Some gh -> VersionSpec.Source gh
            | None ->
              begin match String.cut ~sep:"git+" spec with
              | Some ("", remote) ->
                let remote, ref = parseRef remote in
                VersionSpec.Source (SourceSpec.Git {remote; ref})
              | _ -> VersionSpec.Npm (NpmVersion.Formula.parse spec)
              end
        in {name; spec;}

  let%test "make: parsing git spec" =
    let req = make ~name:"pkg" ~spec:"git+https://some/repo" in
    req.spec = VersionSpec.Source (SourceSpec.Git {remote = "https://some/repo"; ref = None})

  let%test "make: parsing git spec with ref" =
    let req = make ~name:"pkg" ~spec:"git+https://some/repo#ref" in
    req.spec = VersionSpec.Source (SourceSpec.Git {remote = "https://some/repo"; ref = Some "ref"})
  let%test "make: parsing git spec with command" =
    let req = make
      ~name:"eslint"
      ~spec:"git+https://github.com/eslint/eslint.git#9d6223040316456557e0a2383afd96be90d28c5a"
    in
    req.spec = VersionSpec.Source (
      SourceSpec.Git {
        remote = "https://github.com/eslint/eslint.git";
        ref = Some "9d6223040316456557e0a2383afd96be90d28c5a"
      })

  let ofSpec ~name ~spec =
    {name; spec}

  let name req = req.name
  let spec req = req.spec
end

module Dependencies = struct

  type t = Req.t list

  let empty = []

  let add ~req deps = req::deps
  let addMany ~reqs deps = reqs @ deps

  let override ~req deps =
    let f (seen, deps) r =
      if r.Req.name = req.Req.name
      then `Seen, req::deps
      else seen, r::deps
    in
    match List.fold_left ~f ~init:(`Never, []) deps with
    | `Never, deps -> req::deps
    | `Seen, deps -> deps

  let overrideMany ~reqs deps =
    let f deps req = override ~req deps in
    List.fold_left ~f ~init:deps reqs

  let map ~f deps = List.map ~f deps

  let findByName ~name deps =
    let f req = req.Req.name = name in
    List.find_opt ~f deps

  let toList deps = deps

  let pp fmt deps =
    Fmt.pf fmt "@[<hov>[@;%a@;]@]" (Fmt.list ~sep:(Fmt.unit ", ") Req.pp) deps

  let of_yojson json =
    let open Result.Syntax in
    let%bind items = Json.Parse.assoc json in
    let f deps (name, json) =
      let%bind spec = Json.Parse.string json in
      let req = Req.make ~name ~spec in
      return (req::deps)
    in
    Result.List.foldLeft ~f ~init:empty items

  let to_yojson (deps : t) =
    let items =
      let f req = (req.Req.name, Req.to_yojson req) in
      List.map ~f deps
    in
    `Assoc items

  let%test "overrideMany overrides dependency" =
    let a = [Req.make ~name:"prev" ~spec:"1.0.0"; Req.make ~name:"pkg" ~spec:"^1.0.0"] in
    let b = [Req.make ~name:"pkg" ~spec:"^2.0.0"; Req.make ~name:"new" ~spec:"1.0.0"] in
    let r = overrideMany ~reqs:b a in
    r = [
      Req.make ~name:"new" ~spec:"1.0.0";
      Req.make ~name:"prev" ~spec:"1.0.0";
      Req.make ~name:"pkg" ~spec:"^2.0.0";
    ]
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

  let apply resolutions req =
    let name = Req.name req in
    match find resolutions name with
    | Some version ->
      let spec = VersionSpec.ofVersion version in
      Some (Req.ofSpec ~name ~spec)
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

module OpamInfo = struct
  type t = {
    packageJson : Json.t;
    files : (Path.t * string) list;
    patches : string list;
  }
  [@@deriving (yojson, show)]
end
