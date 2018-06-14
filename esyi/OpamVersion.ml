module MakeFormula = Version.Formula.Make

(** opam versions are Debian-style versions *)
module Version = DebianVersion

(**
 * Npm formulas over opam versions.
 *)
module Formula = struct

  include MakeFormula(Version)

  let any: dnf = OR [AND [Constraint.ANY]];

  module C = Constraint

  let nextForCaret v =
    let next =
      match Version.AsSemver.major v with
      | Some 0 -> Version.AsSemver.nextPatch v
      | Some _ -> Version.AsSemver.nextMinor v
      | None -> None
    in match next with
    | Some next -> Ok next
    | None ->
      let msg = Printf.sprintf
        "unable to apply ^ version operator to %s"
        (Version.toString v)
      in
      Error msg

  let nextForTilde v =
    match Version.AsSemver.nextPatch v with
    | Some next -> Ok next
    | None ->
      let msg = Printf.sprintf
        "unable to apply ~ version operator to %s"
        (Version.toString v)
      in
      Error msg

  let parseRel text =
    let module String = Astring.String in
    let open Result.Syntax in
    match String.trim text with
    | "*"  | "" -> return [C.ANY]
    | text ->
      begin match text.[0], text.[1] with
      | '^', _ ->
        let text = String.Sub.(text |> v ~start:1 |> to_string) in
        let%bind v = Version.parse text in
        let%bind next = nextForCaret v in
        return [C.GTE v; C.LT next]
      | '~', _ ->
        let text = String.Sub.(text |> v ~start:1 |> to_string) in
        let%bind v = Version.parse text in
        let%bind next = nextForTilde v in
        return [C.GTE v; C.LT next]
      | '=', _ ->
        let text = String.Sub.(text |> v ~start:1 |> to_string) in
        let%bind v = Version.parse text in
        return [C.EQ v]
      | '<', '=' ->
        let text = String.Sub.(text |> v ~start:2 |> to_string) in
        let%bind v = Version.parse text in
        return [C.LTE v]
      | '<', _ ->
        let text = String.Sub.(text |> v ~start:1 |> to_string) in
        let%bind v = Version.parse text in
        return [C.LT v]
      | '>', '=' ->
        let text = String.Sub.(text |> v ~start:2 |> to_string) in
        let%bind v = Version.parse text in
        return [C.GTE v]
      | '>', _ ->
        let text = String.Sub.(text |> v ~start:1 |> to_string) in
        let%bind v = Version.parse text in
        return [C.GT v]
      | _, _ ->
        let%bind v = Version.parse text in
        return [C.EQ v]
      end

  (* TODO: do not use failwith here *)
  let parse v =
    let parseSimple v =
      let parse v =
        let v = String.trim v in
        if v = ""
        then [C.ANY]
        else match parseRel v with
        | Ok v -> v
        | Error err -> failwith ("Error: " ^ err)
      in
      let (AND conjs) = Parse.conjunction ~parse v in
      let conjs =
        let f conjs c = conjs @ c in
        List.fold_left ~init:[] ~f conjs
      in
      let conjs = match conjs with | [] -> [C.ANY] | conjs -> conjs in
      AND conjs
    in
    Parse.disjunction ~parse:parseSimple v

  let%test_module "parse" = (module struct
    let v = Version.parseExn

    let parsesOk f e =
      let pf = parse f in
      if pf <> e
      then failwith ("Received: " ^ (DNF.show pf))
      else ()

    let%test_unit _ = parsesOk ">=1.7.0" (OR [AND [C.GTE (v "1.7.0")]])
    let%test_unit _ = parsesOk "*" (OR [AND [C.ANY]])
    let%test_unit _ = parsesOk "" (OR [AND [C.ANY]])

  end)

  let%test_module "matches" = (module struct
    let v = Version.parseExn
    let f = parse

    let%test _ = DNF.matches ~version:(v "1.8.0") (f ">=1.7.0")
    let%test _ = DNF.matches ~version:(v "0.3") (f "=0.3")
    let%test _ = DNF.matches ~version:(v "0.3") (f "0.3")

  end)


end
