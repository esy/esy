module Source = struct
  type t =
    | Archive of string * string option
    | GitSource of string * string option
    | GithubSource of string * string * string option
    | File of string
    | NoSource
    [@@deriving yojson]
end

let startsWith value needle =
  String.length value > String.length needle
  && String.sub value 0 (String.length needle) = needle

let getOpam  name =
  let ln = 6 in
  if String.length name > ln && String.sub name 0 ln = "@opam/"
  then Some name
  else None

module DependencyRequest = struct
  type t = {
    name: string;
    req: req;
  }

  and req =
    | Npm of NpmVersion.Formula.t 
    | Github of string * string * string option 
    | Opam of OpamVersion.Formula.t 
    | Git of string 
    | LocalPath of EsyLib.Path.t 

  let parseGithubVersion text =
    let parts = Str.split (Str.regexp_string "/") text in
    match parts with
    | org::rest::[] ->
      begin match Str.split (Str.regexp_string "#") rest with
      | repo::ref::[] ->
        Some (Github (org, repo, Some ref))
      | repo::[] ->
        Some (Github (org, repo, None))
      | _ -> None
      end
    | _ -> None

  let to_yojson {name = _; req} =
    match req with
    | Npm version ->
      NpmVersion.Formula.to_yojson version
    | Github (name, repo, Some ref) ->
      `String (name ^ "/" ^ repo ^ "#" ^ ref)
    | Github (name, repo, None) ->
      `String (name ^ "/" ^ repo)
    | Git url ->
      `String url
    | LocalPath path ->
      `String (Path.toString path)
    | Opam version ->
      OpamVersion.Formula.to_yojson version

  let reqToString req =
    match req with
    | Npm  version ->
      NpmVersion.Formula.toString version
    | Github (name, repo, Some ref) ->
      name ^ "/" ^ repo ^ "#" ^ ref
    | Github (name, repo, None) ->
      name ^ "/" ^ repo
    | Git url -> url
    | LocalPath path -> Path.toString path
    | Opam version ->
      OpamVersion.Formula.toString version

  let toString {name; req} =
    name ^ "@" ^ (reqToString req)

  let make name value =
    if startsWith value "." || startsWith value "/"
    then {name; req = LocalPath (Path.v value);}
    else
      match getOpam name with
      | Some name ->
        let req =
          match parseGithubVersion value with
          | Some gh -> gh
          | None -> Opam (OpamVersion.Formula.parse value)
        in {name; req;}
      | None ->
        let req =
          match parseGithubVersion value with
            | Some gh -> gh
            | None ->
              if startsWith value "git+"
              then Git value
              else Npm (NpmVersion.Formula.parse value)
        in {name; req;}
end

module Dependencies = struct

  type t = DependencyRequest.t list

  let empty = []

  let of_yojson json =
    let open Result.Syntax in
    let request (name, json) =
      let%bind value = Json.Parse.string json in
      return (DependencyRequest.make name value)
    in
    let%bind items = Json.Parse.assoc json in
    Result.List.map ~f:request items

  let to_yojson (deps : t) =
    let items =
        List.map
          (fun ({ DependencyRequest.name = name;_} as req) ->
          (name, (DependencyRequest.to_yojson req))) deps
    in
    `Assoc items

  let merge a b =
    let seen =
      let f seen {DependencyRequest.name = name; _} =
        StringSet.add name seen
      in
      List.fold_left f StringSet.empty a
    in
    let f a item =
      if StringSet.mem item.DependencyRequest.name seen
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
