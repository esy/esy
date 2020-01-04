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

let pp_patt fmt v =
  match v with
  | Version v -> Version.pp fmt v
  | Major x -> Format.fprintf fmt "%i.x.x" x
  | Minor (x, y) -> Format.fprintf fmt "%i.%i.x" x y
  | Any -> Format.fprintf fmt "*"

let pp_clause fmt v =
  match v with
  | Patt p -> pp_patt fmt p
  | Spec (spec, p) ->
    Format.fprintf fmt "%a%a" pp_spec spec pp_patt p
  | Expr (op, p) ->
    Format.fprintf fmt "%a%a" pp_op op pp_patt p

let pp_range fmt v =
  match v with
  | Hyphen (a, b) ->
    Format.fprintf fmt "%a - %a" pp_patt a pp_patt b
  | Conj xs ->
    Pp.(pp_list (pp_const " ") pp_clause) fmt xs

let pp = Pp.(pp_list (pp_const " || ") pp_range)

let show v = Format.asprintf "%a" pp v

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
  parse_and_print ">1.1.1";
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
  parse_and_print "^1.1";
  [%expect {| ^1.1.x |}]

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
