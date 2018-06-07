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
end

(**
 * This representes a concrete version which at some point will be resolved to a
 * concrete version Version.t.
 *)
module VersionSpec = struct

  type t =
    | Npm of NpmVersion.Formula.t
    | Opam of OpamVersion.Formula.t
    | Source of SourceSpec.t

  let toString = function
    | Npm formula -> NpmVersion.Formula.toString formula
    | Opam formula -> "opam:" ^ OpamVersion.Formula.toString formula
    | Source src -> SourceSpec.toString src

  let to_yojson src = `String (toString src)
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
    print_endline "making req";
    print_endline ("      name: " ^ name);
    print_endline ("      spec: " ^ spec);

    let parseGitHubSpec text =
      let parts = Str.split (Str.regexp_string "/") text in
      match parts with
      | org::rest::[] ->
        begin match Str.split (Str.regexp_string "#") rest with
        | repo::ref::[] ->
          Some (SourceSpec.Github (org, repo, Some ref))
        | repo::[] ->
          Some (SourceSpec.Github (org, repo, None))
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
    print_endline "making req";
    print_endline ("      name: " ^ name);
    print_endline ("      spec: " ^ VersionSpec.toString spec);
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
          (fun ({ Req.name = name;_} as req) ->
          (name, (Req.to_yojson req))) deps
    in
    `Assoc items

  let merge a b =
    let seen =
      let f seen {Req.name = name; _} =
        StringSet.add name seen
      in
      List.fold_left f StringSet.empty a
    in
    let f a item =
      if StringSet.mem item.Req.name seen
      then a
      else item::a
    in
    List.fold_left f a b
end

module DependenciesInfo = struct
  type t = {
    dependencies: (Dependencies.t [@default Dependencies.empty]);
    buildDependencies: (Dependencies.t [@default Dependencies.empty]);
    devDependencies: (Dependencies.t [@default Dependencies.empty]);
  }
  [@@deriving yojson { strict = false }]
end

module OpamInfo = struct
  type t = Json.t * (Path.t * string) list * string list
  [@@deriving yojson]
end
