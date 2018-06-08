module MakeFormula = Version.Formula.Make

(** opam versions are Debian-style versions *)
module Version = DebianVersion

(**
 * Npm formulas over opam versions.
 *)
module Formula = struct

  include MakeFormula(Version)

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
    | "*"  | "" -> return ANY
    | text ->
      begin match text.[0], text.[1] with
      | '^', _ ->
        let text = String.Sub.(text |> v ~start:1 |> to_string) in
        let%bind v = Version.parse text in
        let%bind next = nextForCaret v in
        return (AND ((GTE v), (LT next)))
      | '~', _ ->
        let text = String.Sub.(text |> v ~start:1 |> to_string) in
        let%bind v = Version.parse text in
        let%bind next = nextForTilde v in
        return (AND ((GTE v), (LT next)))
      | '=', _ ->
        let text = String.Sub.(text |> v ~start:1 |> to_string) in
        let%bind v = Version.parse text in
        return (EQ v)
      | '<', '=' ->
        let text = String.Sub.(text |> v ~start:2 |> to_string) in
        let%bind v = Version.parse text in
        return (LTE v)
      | '<', _ ->
        let text = String.Sub.(text |> v ~start:1 |> to_string) in
        let%bind v = Version.parse text in
        return (LT v)
      | '>', '=' ->
        let text = String.Sub.(text |> v ~start:2 |> to_string) in
        let%bind v = Version.parse text in
        return (GTE v)
      | '>', _ ->
        let text = String.Sub.(text |> v ~start:1 |> to_string) in
        let%bind v = Version.parse text in
        return (GT v)
      | _, _ ->
        let%bind v = Version.parse text in
        return (EQ v)
      end

  (* TODO: do not use failwith here *)
  let parse v =
    let parseSimple v =
      let parse v =
        match parseRel v with
        | Ok v -> v
        | Error err -> failwith err
        in
      Parse.conjunction parse v
    in
    Parse.disjunction parseSimple v

  let%test_module "matches" = (module struct
    let v = Version.parseExn
    let f = parse

    let%test _ =
      matches (f ">=1.7.0") (v "1.8.0")

  end)

end
