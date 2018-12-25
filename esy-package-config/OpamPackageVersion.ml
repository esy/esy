module String = Astring.String
module P = Parse

(** opam versions are Debian-style versions *)
module Version = struct
  type t = OpamPackage.Version.t

  let compare = OpamPackage.Version.compare
  let show = OpamPackage.Version.to_string
  let pp fmt v = Fmt.pf fmt "opam:%s" (show v)
  let parse v = Ok (OpamPackage.Version.of_string v)
  let parser =
    Parse.(
      let%bind input = take_while1 (fun _ -> true) in
      try return (OpamPackage.Version.of_string input)
      with _ -> fail "cannot parse opam version"
    )
  let parseExn v = OpamPackage.Version.of_string v
  let majorMinorPatch _v = None
  let prerelease _v = false
  let stripPrerelease v = v
  let to_yojson v = `String (show v)
  let of_yojson = function
    | `String v -> parse v
    | _ -> Error "expected a string"

  let ofSemver v =
    let v = SemverVersion.Version.show v in
    parse v

  let sexp_of_t v =
    Sexplib0.Sexp.(List [Atom "Opam"; Atom (show v);])
end

let caretRange v =
  match SemverVersion.Version.parse v with
  | Ok v ->
    let open Result.Syntax in
    let ve =
      if v.major = 0
      then {v with minor = v.minor + 1}
      else {v with major = v.major + 1}
    in
    let%bind v = Version.ofSemver v in
    let%bind ve = Version.ofSemver ve in
    Ok (v, ve)
  | Error _ -> Error ("^ cannot be applied to: " ^ v)

let tildaRange v =
  match SemverVersion.Version.parse v with
  | Ok v ->
    let open Result.Syntax in
    let ve = {v with minor = v.minor + 1} in
    let%bind v = Version.ofSemver v in
    let%bind ve = Version.ofSemver ve in
    Ok (v, ve)
  | Error _ -> Error ("~ cannot be applied to: " ^ v)

module Constraint = VersionBase.Constraint.Make(Version)

(**
 * Npm formulas over opam versions.
 *)
module Formula = struct

  include VersionBase.Formula.Make(Version)(Constraint)

  let any: DNF.t = [[Constraint.ANY]];

  module C = Constraint

  let parseRel text =
    let module String = Astring.String in
    let open Result.Syntax in
    match String.trim text with
    | "*"  | "" -> return [C.ANY]
    | text ->
      let len = String.length text in
      let fst = if len > 0 then Some text.[0] else None in
      let snd = if len > 1 then Some text.[1] else None in
      begin match fst, snd with
      | Some '^', _ ->
        let v = String.Sub.(text |> v ~start:1 |> to_string) in
        let%bind v, ve = caretRange v in
        return [C.GTE v; C.LT ve]
      | Some '~', _ ->
        let v = String.Sub.(text |> v ~start:1 |> to_string) in
        let%bind v, ve = tildaRange v in
        return [C.GTE v; C.LT ve]
      | Some '=', _ ->
        let text = String.Sub.(text |> v ~start:1 |> to_string) in
        let%bind v = Version.parse text in
        return [C.EQ v]
      | Some '<', Some '=' ->
        let text = String.Sub.(text |> v ~start:2 |> to_string) in
        let%bind v = Version.parse text in
        return [C.LTE v]
      | Some '<', _ ->
        let text = String.Sub.(text |> v ~start:1 |> to_string) in
        let%bind v = Version.parse text in
        return [C.LT v]
      | Some '>', Some '=' ->
        let text = String.Sub.(text |> v ~start:2 |> to_string) in
        let%bind v = Version.parse text in
        return [C.GTE v]
      | Some '>', _ ->
        let text = String.Sub.(text |> v ~start:1 |> to_string) in
        let%bind v = Version.parse text in
        return [C.GT v]
      | _, _ ->
        let%bind v = Version.parse text in
        return [C.EQ v]
      end

  let parseExn v =
    let parseSimple v =
      let parse v =
        let v = String.trim v in
        if v = ""
        then [C.ANY]
        else match parseRel v with
        | Ok v -> v
        | Error err -> failwith ("Error: " ^ err)
      in
      let (conjs) = ParseUtils.conjunction ~parse v in
      let conjs =
        let f conjs c = conjs @ c in
        List.fold_left ~init:[] ~f conjs
      in
      let conjs = match conjs with | [] -> [C.ANY] | conjs -> conjs in
      conjs
    in
    ParseUtils.disjunction ~parse:parseSimple v

  let parse v =
    try Ok (parseExn v)
    with _ ->
      let msg = "unable to parse formula: " ^ v in
      Error msg

  let parserDnf =
    P.(
      let%bind input = take_while1 (fun _ -> true) in
      return (parseExn input)
    )

  let%test_module "parse" = (module struct
    let v = Version.parseExn

    let parsesOk f e =
      let pf = parseExn f in
      if pf <> e
      then failwith ("Received: " ^ (DNF.show pf))
      else ()

    let%test_unit _ = parsesOk ">=1.7.0" ([[C.GTE (v "1.7.0")]])
    let%test_unit _ = parsesOk "*" ([[C.ANY]])
    let%test_unit _ = parsesOk "" ([[C.ANY]])

  end)

  let%test_module "matches" = (module struct
    let v = Version.parseExn
    let f = parseExn

    let%test _ = DNF.matches ~version:(v "1.8.0") (f ">=1.7.0")
    let%test _ = DNF.matches ~version:(v "0.3") (f "=0.3")
    let%test _ = DNF.matches ~version:(v "0.3") (f "0.3")

  end)


end
