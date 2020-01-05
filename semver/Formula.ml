include Import.Formula

module Pp = Import.Pp

let parse v =
  let lexbuf = Lexing.from_string v in
  match Parser.parse_formula Lexer.tokenize lexbuf with
  | exception Lexer.Error msg -> Error msg
  | exception Parser.Error ->
    let pos = lexbuf.Lexing.lex_curr_p.pos_cnum in
    let msg = Printf.sprintf "error parsing: %i column" pos in
    Error msg
  | v -> Ok v

let pp_op fmt v =
  match v with
  | GT -> Pp.pp_const ">" fmt ()
  | LT -> Pp.pp_const "<" fmt ()
  | EQ -> Pp.pp_const "" fmt ()
  | GTE -> Pp.pp_const ">=" fmt ()
  | LTE -> Pp.pp_const "<=" fmt ()

let pp_spec fmt v =
  match v with
  | Tilda -> Pp.pp_const "~" fmt ()
  | Caret -> Pp.pp_const "^" fmt ()

let pp_pattern fmt v =
  match v with
  | Major x -> Format.fprintf fmt "%i.x.x" x
  | Minor (x, y) -> Format.fprintf fmt "%i.%i.x" x y
  | Any -> Format.fprintf fmt "*"

let pp_version_or_pattern fmt v =
  match v with
  | Version v -> Version.pp fmt v
  | Pattern v -> pp_pattern fmt v

let pp_clause fmt v =
  match v with
  | Patt p -> pp_version_or_pattern fmt p
  | Spec (spec, p) ->
    Format.fprintf fmt "%a%a" pp_spec spec pp_version_or_pattern p
  | Expr (op, p) ->
    Format.fprintf fmt "%a%a" pp_op op pp_version_or_pattern p

let pp_range fmt v =
  match v with
  | Hyphen (a, b) ->
    Format.fprintf fmt
      "%a - %a"
      pp_version_or_pattern a pp_version_or_pattern b
  | Simple xs ->
    Pp.(pp_list (pp_const " ") pp_clause) fmt xs

let pp = Pp.(pp_list (pp_const " || ") pp_range)

let show v = Format.asprintf "%a" pp v

module N = struct
  type t = (op * Version.t) list list

  let of_formula ranges =
    let to_version = function
      | Any -> Version.make 0 0 0
      | Major major -> Version.make major 0 0
      | Minor (major, minor) -> Version.make major minor 0
    in
    let to_next_version = function
      | Any -> Version.make 0 0 0
      | Major major -> Version.make (major + 1) 0 0
      | Minor (major, minor) -> Version.make major (minor + 1) 0
    in
    let conv_hyphen a b =
      let a =
        match a with
        | Version a -> Some (GTE, a)
        | Pattern Any  -> None
        | Pattern a -> Some (GTE, to_version a)
      in
      let b =
        match b with
        | Version b -> Some (LTE, b)
        | Pattern Any -> None
        | Pattern b -> Some (LT, to_next_version b)
      in
      a, b
    in
    let conv_tilda v =
      match v with
      | Version v ->
        (GTE, v),
        (LT, Version.next_minor v)
      | Pattern p ->
        (GTE, to_version p),
        (LT, to_next_version p)
    in
    let conv_caret v =
      match v with
      | Version ({major = 0; minor = 0; _} as v) ->
        (GTE, v),
        Some (LT, Version.next_patch v)
      | Version ({major = 0; _} as v) ->
        (GTE, v),
        Some (LT, Version.next_minor v)
      | Version v ->
        (GTE, v),
        Some (LT, Version.next_major v)
      | Pattern Any ->
        (GTE, (to_version Any)),
        None
      | Pattern ((Major _) as p) ->
        let v = to_version p in
        (GTE, v),
        Some (LT, Version.(next_major v))
      | Pattern (Minor (0, _) as p) ->
        let v = to_version p in
        (GTE, v),
        Some (LT, Version.next_minor v)
      | Pattern (Minor _ as p) ->
        let v = to_version p in
        (GTE, v),
        Some (LT, Version.next_major v)
    in
    let conv_x_range p =
      match p with
      | Any -> (GTE, to_version p), None
      | _ -> (GTE, to_version p), Some (LT, to_next_version p)
    in
    ListLabels.map ranges ~f:(function
      | Hyphen (left, right) ->
        begin match conv_hyphen left right with
        | Some left, Some right -> [left; right]
        | Some left, None -> [left]
        | None, Some right -> [right]
        | None, None -> [GTE, Version.make 0 0 0]
        end
      | Simple xs ->
        xs
        |> ListLabels.fold_left ~init:[] ~f:(fun acc -> function
          | Expr (_, _) -> assert false
          | Spec (Caret, v) ->
            begin match conv_caret v with
            | left, Some right -> right::left::acc
            | left, None -> left::acc
            end
          | Spec (Tilda, v) ->
            let left, right = conv_tilda v in
            right::left::acc
          | Patt (Version v) ->
            (EQ, v)::acc
          | Patt (Pattern p) ->
            begin match conv_x_range p with
            | left, Some right -> right::left::acc
            | left, None -> left::acc
            end
        )
        |> ListLabels.rev
    )

  let to_formula disj =
    ListLabels.map disj ~f:(fun conj ->
      Simple (ListLabels.map conj ~f:(fun (op, v) ->
        Expr (op, Version v))))

  let pp fmt v = pp fmt (to_formula v)
  let show v = Format.asprintf "%a" pp v

  let parse_simplify_and_print v =
    match parse v with
    | Ok v ->
      Format.printf "%a" pp (of_formula v)
    | Error msg ->
      Format.printf "ERROR: %s" msg

  (* hyphen ranges *)

  let%expect_test _ =
    parse_simplify_and_print "1.2.3 - 2.3.4";
    [%expect {| >=1.2.3 <=2.3.4 |}]

  let%expect_test _ =
    parse_simplify_and_print "1.2 - 2.3.4";
    [%expect {| >=1.2.0 <=2.3.4 |}]

  let%expect_test _ =
    parse_simplify_and_print "1.2.3 - 2.3";
    [%expect {| >=1.2.3 <2.4.0 |}]

  let%expect_test _ =
    parse_simplify_and_print "1.2.3 - 2";
    [%expect {| >=1.2.3 <3.0.0 |}]

  (* not documented at node-semver so we choose reasonable behaviour here *)
  let%expect_test _ =
    parse_simplify_and_print "1.2.3 - *";
    [%expect {| >=1.2.3 |}]

  (* not documented at node-semver so we choose reasonable behaviour here *)
  let%expect_test _ =
    parse_simplify_and_print "* - 1.2.3";
    [%expect {| <=1.2.3 |}]

  (* not documented at node-semver so we choose reasonable behaviour here *)
  let%expect_test _ =
    parse_simplify_and_print "* - *";
    [%expect {| >=0.0.0 |}]

  (* x-ranges *)

  let%expect_test _ =
    parse_simplify_and_print "*";
    [%expect {| >=0.0.0 |}]

  let%expect_test _ =
    parse_simplify_and_print "1.x";
    [%expect {| >=1.0.0 <2.0.0 |}]

  let%expect_test _ =
    parse_simplify_and_print "1.2.x";
    [%expect {| >=1.2.0 <1.3.0 |}]

  let%expect_test _ =
    parse_simplify_and_print "";
    [%expect {| >=0.0.0 |}]

  let%expect_test _ =
    parse_simplify_and_print "1";
    [%expect {| >=1.0.0 <2.0.0 |}]

  let%expect_test _ =
    parse_simplify_and_print "1.2";
    [%expect {| >=1.2.0 <1.3.0 |}]

  (* tilda ranges *)

  let%expect_test _ =
    parse_simplify_and_print "~1.2.3";
    [%expect {| >=1.2.3 <1.3.0 |}]

  let%expect_test _ =
    parse_simplify_and_print "~1.2";
    [%expect {| >=1.2.0 <1.3.0 |}]

  let%expect_test _ =
    parse_simplify_and_print "~1";
    [%expect {| >=1.0.0 <2.0.0 |}]

  let%expect_test _ =
    parse_simplify_and_print "~0.2.3";
    [%expect {| >=0.2.3 <0.3.0 |}]

  let%expect_test _ =
    parse_simplify_and_print "~0.2";
    [%expect {| >=0.2.0 <0.3.0 |}]

  let%expect_test _ =
    parse_simplify_and_print "~0";
    [%expect {| >=0.0.0 <1.0.0 |}]

  let%expect_test _ =
    parse_simplify_and_print "~1.2.3-beta.2";
    [%expect {| >=1.2.3-beta.2 <1.3.0 |}]

  (* caret ranges *)

  let%expect_test _ =
    parse_simplify_and_print "^1.2.3";
    [%expect {| >=1.2.3 <2.0.0 |}]

  let%expect_test _ =
    parse_simplify_and_print "^0.2.3";
    [%expect {| >=0.2.3 <0.3.0 |}]

  let%expect_test _ =
    parse_simplify_and_print "^0.0.3";
    [%expect {| >=0.0.3 <0.0.4 |}]

  let%expect_test _ =
    parse_simplify_and_print "^1.2.3-beta.2";
    [%expect {| >=1.2.3-beta.2 <2.0.0 |}]

  let%expect_test _ =
    parse_simplify_and_print "^0.0.3-beta";
    [%expect {| >=0.0.3-beta <0.0.4 |}]

  let%expect_test _ =
    parse_simplify_and_print "^1.2.x";
    [%expect {| >=1.2.0 <2.0.0 |}]

  let%expect_test _ =
    parse_simplify_and_print "^0.0.x";
    [%expect {| >=0.0.0 <0.1.0 |}]

  let%expect_test _ =
    parse_simplify_and_print "^0.0";
    [%expect {| >=0.0.0 <0.1.0 |}]

  let%expect_test _ =
    parse_simplify_and_print "^1.x";
    [%expect {| >=1.0.0 <2.0.0 |}]

  let%expect_test _ =
    parse_simplify_and_print "^0.x";
    [%expect {| >=0.0.0 <1.0.0 |}]

  let%expect_test _ =
    parse_simplify_and_print "^*";
    [%expect {| >=0.0.0 |}]

end

let normalize = N.of_formula

let parse_and_print v =
  match parse v with
  | Ok v ->
    Format.printf "%a" pp v
  | Error msg ->
    Format.printf "ERROR: %s" msg

let%expect_test _ =
  parse_and_print "1.1.1";
  [%expect {| 1.1.1 |}]

let%expect_test _ =
  parse_and_print "1.1";
  [%expect {| 1.1.x |}]

let%expect_test _ =
  parse_and_print "1";
  [%expect {| 1.x.x |}]

let%expect_test _ =
  parse_and_print "";
  [%expect {| * |}]

let%expect_test _ =
  parse_and_print "x";
  [%expect {| * |}]

let%expect_test _ =
  parse_and_print "X";
  [%expect {| * |}]

let%expect_test _ =
  parse_and_print "*";
  [%expect {| * |}]

let%expect_test _ =
  parse_and_print "=1.1.1";
  [%expect {| 1.1.1 |}]

let%expect_test _ =
  parse_and_print "v1.1.1";
  [%expect {| 1.1.1 |}]

let%expect_test _ =
  parse_and_print ">1.1.1";
  [%expect {| >1.1.1 |}]

let%expect_test _ =
  parse_and_print ">v1.1.1";
  [%expect {| >1.1.1 |}]

let%expect_test _ =
  parse_and_print ">=1.1.1";
  [%expect {| >=1.1.1 |}]

let%expect_test _ =
  parse_and_print "<1.1.1";
  [%expect {| <1.1.1 |}]

let%expect_test _ =
  parse_and_print "<=1.1.1";
  [%expect {| <=1.1.1 |}]

let%expect_test _ =
  parse_and_print "<= 1.1.1";
  [%expect {| <=1.1.1 |}]

let%expect_test _ =
  parse_and_print "^1.1.1";
  [%expect {| ^1.1.1 |}]

let%expect_test _ =
  parse_and_print "~1.1.1";
  [%expect {| ~1.1.1 |}]

let%expect_test _ =
  parse_and_print ">1.1";
  [%expect {| >1.1.x |}]

let%expect_test _ =
  parse_and_print ">v1.1";
  [%expect {| >1.1.x |}]

let%expect_test _ =
  parse_and_print "^1.1";
  [%expect {| ^1.1.x |}]

let%expect_test _ =
  parse_and_print ">1";
  [%expect {| >1.x.x |}]

let%expect_test _ =
  parse_and_print ">v1";
  [%expect {| >1.x.x |}]

let%expect_test _ =
  parse_and_print "^1";
  [%expect {| ^1.x.x |}]

let%expect_test _ =
  parse_and_print ">1.1.1 <2";
  [%expect {| >1.1.1 <2.x.x |}]

let%expect_test _ =
  parse_and_print "1 || 2";
  [%expect {| 1.x.x || 2.x.x |}]

let%expect_test _ =
  parse_and_print "v1 || 2";
  [%expect {| 1.x.x || 2.x.x |}]

let%expect_test _ =
  parse_and_print "1|| 2";
  [%expect {| 1.x.x || 2.x.x |}]

let%expect_test _ =
  parse_and_print "1 ||2";
  [%expect {| 1.x.x || 2.x.x |}]

let%expect_test _ =
  parse_and_print "1||2";
  [%expect {| 1.x.x || 2.x.x |}]

let%expect_test _ =
  parse_and_print "1 - 2";
  [%expect {| 1.x.x - 2.x.x |}]

let%expect_test _ =
  parse_and_print "1 -  2";
  [%expect {| 1.x.x - 2.x.x |}]

let%expect_test _ =
  parse_and_print "1  -  2";
  [%expect {| 1.x.x - 2.x.x |}]

let%expect_test _ =
  parse_and_print "1  - 2";
  [%expect {| 1.x.x - 2.x.x |}]
