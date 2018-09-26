type t =
  | Npm of SemverVersion.Formula.DNF.t
  | NpmDistTag of string
  | Opam of OpamPackageVersion.Formula.DNF.t
  | Source of SourceSpec.t
  [@@deriving ord]

let show = function
  | Npm formula -> SemverVersion.Formula.DNF.show formula
  | NpmDistTag tag -> tag
  | Opam formula -> OpamPackageVersion.Formula.DNF.show formula
  | Source src -> SourceSpec.show src

let pp fmt spec =
  Fmt.string fmt (show spec)

let to_yojson src = `String (show src)

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
      NpmDistTag tag
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
