module MakeFormula = Version.Formula.Make

(** opam versions are Debian-style versions *)
module Version = struct
  type t = OpamPackage.Version.t

  let equal a b = OpamPackage.Version.compare a b = 0
  let compare = OpamPackage.Version.compare
  let show = OpamPackage.Version.to_string
  let pp fmt v = Fmt.pf fmt "%s" (show v)
  let parse v = Ok (OpamPackage.Version.of_string v)
  let parseExn v = OpamPackage.Version.of_string v
  let prerelease _v = false
  let stripPrerelease v = v
  let toString = OpamPackage.Version.to_string
  let to_yojson v = `String (show v)
  let of_yojson = function
    | `String v -> parse v
    | _ -> Error "expected a string"
end

(**
 * Npm formulas over opam versions.
 *)
module Formula = struct

  include MakeFormula(Version)

  let any: DNF.t = OR [AND [Constraint.ANY]];

  module C = Constraint

  let parseRel text =
    let module String = Astring.String in
    let open Result.Syntax in
    match String.trim text with
    | "*"  | "" -> return [C.ANY]
    | text ->
      begin match text.[0], text.[1] with
      | '^', _ ->
        let msg = Printf.sprintf "%s: ^ is not supported for opam versions" text in
        error msg
      | '~', _ ->
        let msg = Printf.sprintf "%s: ~ is not supported for opam versions" text in
        error msg
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
