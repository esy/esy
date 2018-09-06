module AdHocParse : sig
  type 'a t = string -> ('a, string) result

  val (or) : 'a t -> 'a t -> 'a t

end = struct
  type 'a t = string -> ('a, string) result

  let (or) a b s =
    match a s with
    | Ok v -> Ok v
    | Error _ -> b s

end

module SourceParamSyntax : sig
  type t = string option * string StringMap.t

  val extract : (string * t) AdHocParse.t

end = struct

  type t = string option * string StringMap.t

  let empty = None, StringMap.empty

  let parse value =
    let open Result.Syntax in
    let parts = Astring.String.cuts ~sep:"&" value in
    let%bind default, named =
      let f (default, named) part =
        match default, Astring.String.cut ~sep:"=" part with
        | None, None -> return (Some part, named)
        | Some _, None -> error "invalid source parameter"
        | _, Some ("", _) -> error "invalid source parameter"
        | _, Some (k, v) -> return (default, StringMap.add k v named)
      in
      Result.List.foldLeft ~f ~init:(None, StringMap.empty) parts
    in
    return (default, named)

  let extract value =
    let open Result.Syntax in
    match Astring.String.cut ~sep:"#" value with
    | None -> return (value, empty)
    | Some (_, "") -> error "empty parameters"
    | Some (value, params) ->
      let%bind params = parse params in
      return (value, params)
end

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
    match Astring.String.cut ~sep:"#" spec with
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

  let github spec =
    let open Result.Syntax in

    let normalizeGithubRepo repo =
      match Astring.String.cut ~sep:".git" repo with
      | Some (repo, "") -> repo
      | Some _ -> repo
      | None -> repo
    in

    match Astring.String.cut ~sep:"/" spec with
    | Some (user, rest) ->
      let%bind repo, (ref, params) = SourceParamSyntax.extract rest in
      return (Source (SourceSpec.Github {
        user;
        repo = normalizeGithubRepo repo;
        ref;
        manifestFilename = StringMap.find "manifestFilename" params;
      }))
    | _ -> error "not a github source"

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

  let sourceWithProto spec =
    let open Result.Syntax in
    match parseProto spec with
    | Some ("link:", spec) ->
      let%bind path, (_, params) = SourceParamSyntax.extract spec in
      let path = Path.(normalizeAndRemoveEmptySeg (v path)) in
      let spec = SourceSpec.LocalPathLink {
        path;
        manifestFilename = StringMap.find "manifestFilename" params;
      } in
      return (Source spec)
    | Some ("file:", spec) ->
      let%bind path, (_, params) = SourceParamSyntax.extract spec in
      let path = Path.(normalizeAndRemoveEmptySeg (v path)) in
      let spec = SourceSpec.LocalPath {
        path;
        manifestFilename = StringMap.find "manifestFilename" params;
      } in
      return (Source spec)
    | Some ("https:", _)
    | Some ("http:", _) ->
      let%bind url, checksum = parseChecksum spec in
      let spec = SourceSpec.Archive {url; checksum} in
      return (Source spec)
    | Some ("git+", spec) ->
      let%bind remote, (ref, params) = SourceParamSyntax.extract spec in
      let spec = SourceSpec.Git {
        remote;
        ref;
        manifestFilename = StringMap.find "manifestFilename" params;
      } in
      return (Source spec)
    | Some ("git:", _) ->
      let%bind remote, (ref, params) = SourceParamSyntax.extract spec in
      let spec = SourceSpec.Git {
        remote;
        ref;
        manifestFilename = StringMap.find "manifestFilename" params;
      } in
      return (Source spec)
    | Some ("npm:", v) ->
      begin match Astring.String.cut ~rev:true ~sep:"@" v with
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
    let open Result.Syntax in
    if Astring.String.is_prefix ~affix:"." spec || Astring.String.is_prefix ~affix:"/" spec
    then
      let%bind path, (_, params) = SourceParamSyntax.extract spec in
      let path = Path.(normalizeAndRemoveEmptySeg (v path)) in
      return (Source (SourceSpec.LocalPath {
        path;
        manifestFilename = StringMap.find "manifestFilename" params;
      }))
    else
      error "not a path"

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
