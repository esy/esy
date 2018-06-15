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
    | Git of string * string
    | Github of string * string * string
    | LocalPath of Path.t
    | NoSource
  [@@deriving (ord)]

  let toString = function
    | Github (user, repo, ref) -> "github:" ^ user ^ "/" ^ repo ^ "#" ^ ref
    | Git (url, commit) -> "git:" ^ url ^ "#" ^ commit
    | Archive (url, checksum) -> "archive:" ^ url ^ "#" ^ checksum
    | LocalPath path -> "path:" ^ Path.toString(path)
    | NoSource -> "no-source:"

  let parse v =
    let open Result.Syntax in
    match%bind Parse.cutWith ":" v with
    | "github", v ->
      let%bind user, v = Parse.cutWith "/" v in
      let%bind name, commit = Parse.cutWith "#" v in
      return (Github (user, name, commit))
    | "git", v ->
      let%bind url, commit = Parse.cutWith "#" v in
      return (Git (url, commit))
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

end

(**
 * A concrete version.
 *)
module Version = struct
  type t =
    | Npm of NpmVersion.Version.t
    | Opam of OpamVersion.Version.t
    | Source of Source.t
    [@@deriving (ord)]

  let toString v =
    match v with
    | Npm t -> NpmVersion.Version.toString(t)
    | Opam v -> "opam:" ^ OpamVersion.Version.toString(v)
    | Source src -> (Source.toString src)

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
    | Git of string * string option
    | Github of string * string * string option
    | LocalPath of Path.t
    | NoSource

  let toString = function
    | Github (user, repo, None) -> "github:" ^ user ^ "/" ^ repo
    | Github (user, repo, Some ref) -> "github:" ^ user ^ "/" ^ repo ^ "#" ^ ref
    | Git (url, Some ref) -> "git:" ^ url ^ "#" ^ ref
    | Git (url, None) -> "git:" ^ url
    | Archive (url, Some checksum) -> "archive:" ^ url ^ "#" ^ checksum
    | Archive (url, None) -> "archive:" ^ url
    | LocalPath path -> "path:" ^ Path.toString(path)
    | NoSource -> "no-source:"

  let to_yojson src = `String (toString src)

  let ofSource (source : Source.t) =
    match source with
    | Source.Archive (url, checksum) -> Archive (url, Some checksum)
    | Source.Git (url, commit) -> Git (url, Some commit)
    | Source.Github (user, repo, commit) -> Github (user, repo, Some commit)
    | Source.LocalPath p -> LocalPath p
    | Source.NoSource -> NoSource
end

(**
 * This representes a concrete version which at some point will be resolved to a
 * concrete version Version.t.
 *)
module VersionSpec = struct

  type t =
    | Npm of NpmVersion.Formula.dnf
    | Opam of OpamVersion.Formula.dnf
    | Source of SourceSpec.t

  let toString = function
    | Npm formula -> NpmVersion.Formula.DNF.toString formula
    | Opam formula -> "opam:" ^ OpamVersion.Formula.DNF.toString formula
    | Source src -> SourceSpec.toString src

  let to_yojson src = `String (toString src)

  let satisfies ~version spec =
    match spec, version with
    | Npm formula, Version.Npm version ->
      NpmVersion.Formula.DNF.matches ~version formula
    | Opam formula, Version.Opam version ->
      OpamVersion.Formula.DNF.matches ~version formula
    | Source (SourceSpec.LocalPath p1), Version.Source (Source.LocalPath p2) ->
      Path.equal p1 p2
    | Source (SourceSpec.Github (userS, repoS, Some refS)),
      Version.Source (Source.Github (userV, repoV, refV)) ->
      String.(equal userS userV && equal repoS repoV && equal refS refV)
    | Source (SourceSpec.Github (userS, repoS, None)),
      Version.Source (Source.Github (userV, repoV, _)) ->
      String.(equal userS userV && equal repoS repoV)
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

  let make ~name ~spec =
    let parseGitHubSpec text =

      let normalizeGithubRepo repo =
        match String.cut ~sep:".git" repo with
        | Some (repo, "") -> repo
        | Some _ -> repo
        | None -> repo
      in

      let parts = Str.split (Str.regexp_string "/") text in
      match parts with
      | org::rest::[] ->
        begin match Str.split (Str.regexp_string "#") rest with
        | repo::ref::[] ->
          Some (SourceSpec.Github (org, normalizeGithubRepo repo, Some ref))
        | repo::[] ->
          Some (SourceSpec.Github (org, normalizeGithubRepo repo, None))
        | _ -> None
        end
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
              if String.is_prefix ~affix:"git+" spec
              then VersionSpec.Source (SourceSpec.Git (spec, None))
              else VersionSpec.Npm (NpmVersion.Formula.parse spec)
        in {name; spec;}

  let ofSpec ~name ~spec =
    {name; spec}

  let name req = req.name
  let spec req = req.spec
end

module Dependencies = struct

  type t = Req.t list

  let empty = []

  let of_yojson json =
    let open Result.Syntax in
    let request (name, json) =
      let%bind spec = Json.Parse.string json in
      return (Req.make ~name ~spec)
    in
    let%bind items = Json.Parse.assoc json in
    Result.List.map ~f:request items

  let to_yojson (deps : t) =
    let items =
        List.map
          ~f:(fun ({ Req.name = name;_} as req) ->
          (name, (Req.to_yojson req))) deps
    in
    `Assoc items

  let merge a b =
    let seen =
      let f seen {Req.name = name; _} =
        StringSet.add name seen
      in
      List.fold_left ~f ~init:StringSet.empty a
    in
    let f a item =
      if StringSet.mem item.Req.name seen
      then a
      else item::a
    in
    List.fold_left ~f ~init:a b
end

module DependenciesInfo = struct
  type t = {
    dependencies: (Dependencies.t [@default Dependencies.empty]);
    buildDependencies: (Dependencies.t [@default Dependencies.empty]);
    devDependencies: (Dependencies.t [@default Dependencies.empty]);
  }
  [@@deriving yojson { strict = false }]
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

module OpamInfo = struct
  type t = {
    packageJson : Json.t;
    files : (Path.t * string) list;
    patches : string list;
  }
  [@@deriving (yojson, show)]
end
