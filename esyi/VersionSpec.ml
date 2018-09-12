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
  include Parse

  let npmDistTag =
    (* npm dist tags can be any strings which cannot be npm version ranges,
     * this is a simplified check for that. *)
    let p =
      let%map tag = take_while1 (fun _ -> true) in
      NpmDistTag (tag, None)
    in
    match%bind peek_char_fail with
    | 'v' | '0'..'9' -> fail "unable to parse npm tag"
    | _ -> p

  let sourceSpec =
    let%map sourceSpec = SourceSpec.parser in
    Source sourceSpec

  let opamConstraint =
    let%bind spec = take_while1 (fun _ -> true) in
    match OpamPackageVersion.Formula.parse spec with
    | Ok v -> return (Opam v)
    | Error msg -> fail msg

  let npmAnyConstraint =
    return (Npm [[SemverVersion.Constraint.ANY]])

  let npmConstraint =
    let%bind spec = take_while1 (fun _ -> true) in
    match SemverVersion.Formula.parse spec with
    | Ok v -> return (Npm v)
    | Error msg -> fail msg


  let npmWithProto =
    let prefix = string "npm:" in
    let withName = take_while1 (fun c -> c <> '@') *> char '@' *> npmConstraint in
    let withoutName = npmConstraint in
    prefix *> (withName <|> withoutName)

  let parserOpam =
    sourceSpec
    <|> opamConstraint

  let parserNpm =
    sourceSpec
    <|> npmWithProto
    <|> npmConstraint
    <|> npmDistTag
    <|> npmAnyConstraint
end

let parserNpm = Parse.parserNpm
let parserOpam = Parse.parserOpam
