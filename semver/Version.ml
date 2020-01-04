include Types.Version

include struct
  let compare_prerelease_id a b =
    match a, b with
    | N _, A _ -> -1
    | A _, N _ -> 1
    | N a, N b -> Int.compare a b
    | A a, A b -> String.compare a b

  let compare_prerelease a b =
    let rec aux a b =
      match a, b with
      | [], [] -> 0
      | [], _ -> (-1)
      | _, [] -> 1
      | x::xs, y::ys ->
        begin match compare_prerelease_id x y with
        | 0 -> aux xs ys
        | v -> v
        end
    in
    match a, b with
    | [], [] -> 0
    | [], _ -> 1
    | _, [] -> -1
    | a, b -> aux a b

  let compare_build a b =
    let rec aux a b =
      match a, b with
      | [], [] -> 0
      | [], _ -> (-1)
      | _, [] -> 1
      | x::xs, y::ys ->
        begin match String.compare x y with
        | 0 -> aux xs ys
        | v -> v
        end
    in
    match a, b with
    | [], [] -> 0
    | [], _ -> 1
    | _, [] -> -1
    | a, b -> aux a b

  let compare a b =
    match Int.compare a.major b.major with
    | 0 ->
      begin match Int.compare a.minor b.minor with
      | 0 ->
        begin match Int.compare a.patch b.patch with
        | 0 ->
          begin match compare_prerelease a.prerelease b.prerelease with
          | 0 -> compare_build a.build b.build
          | v -> v
          end
        | v -> v
        end
      | v -> v
      end
    | v -> v
end

let parse v =
  let lexbuf = Lexing.from_string v in
  match Parser.parse_version Lexer.tokenize lexbuf with
  | exception Lexer.Error msg -> Error msg
  | exception Parser.Error ->
    let pos = lexbuf.Lexing.lex_curr_p.pos_cnum in
    let msg = Printf.sprintf "error parsing: %i column" pos in
    Error msg
  | v -> Ok v

let pp_list sep pp_item fmt xs =
  match xs with
  | [] -> ()
  | [x] -> pp_item fmt x
  | x::xs ->
    pp_item fmt x;
    List.iter
      (fun p -> Format.pp_print_char fmt sep; pp_item fmt p)
      xs

let pp fmt v =
  Format.fprintf fmt "%i.%i.%i" v.major v.minor v.patch;
  let () =
    match v.prerelease with
    | [] -> ()
    | parts ->
      Format.pp_print_char fmt '-';
      let pp_item fmt = function
        | A p -> Format.pp_print_string fmt p
        | N p -> Format.pp_print_int fmt p
      in
      pp_list '.' pp_item fmt parts
  in
  let () =
    match v.build with
    | [] -> ()
    | parts ->
      Format.pp_print_char fmt '+';
      pp_list '.' Format.pp_print_string fmt parts
  in
  ()

let pp_inspect fmt v =
  let pp_item fmt = function
    | A p -> Format.pp_print_string fmt p
    | N p -> Format.pp_print_int fmt p
  in
  Format.fprintf fmt
    "%i.%i.%i [%a] [%a]"
    v.major v.minor v.patch
    (pp_list ';' pp_item) v.prerelease
    (pp_list ';' Format.pp_print_string) v.build

let show v =
  Format.asprintf "%a" pp v

let parse_and_print v =
  match parse v with
  | Ok v ->
    Format.printf "%a" pp_inspect v
  | Error msg ->
    Format.printf "ERROR: %s" msg

let%expect_test _ =
  parse_and_print "1.1.1";
  [%expect {| 1.1.1 [] [] |}]

let%expect_test _ =
  parse_and_print "1.1.1-1";
  [%expect {| 1.1.1 [1] [] |}]

let%expect_test _ =
  parse_and_print "1.1.1-12.2";
  [%expect {| 1.1.1 [12;2] [] |}]

let%expect_test _ =
  parse_and_print "1.1.1+build";
  [%expect {| 1.1.1 [] [build] |}]

let%expect_test _ =
  parse_and_print "1.1.1+build.another";
  [%expect {| 1.1.1 [] [build;another] |}]

let%expect_test _ =
  parse_and_print "1.1.1-release+build";
  [%expect {| 1.1.1 [release] [build] |}]

let%expect_test _ =
  parse_and_print "1.1.1-rel-2020";
  [%expect {| 1.1.1 [rel-2020] [] |}]

let%expect_test _ =
  parse_and_print "1.1.1-rel-2020-05.12";
  [%expect {| 1.1.1 [rel-2020-05;12] [] |}]

let%expect_test _ =
  parse_and_print "1.1.1-rel-2020+build-2020";
  [%expect {| 1.1.1 [rel-2020] [build-2020] |}]

let%expect_test _ =
  parse_and_print "1.1.1-x";
  [%expect {| 1.1.1 [x] [] |}]

let%expect_test _ =
  parse_and_print "1.1.1--";
  [%expect {| 1.1.1 [-] [] |}]

let%expect_test _ =
  parse_and_print "1.1.1--+-";
  [%expect {| 1.1.1 [-] [-] |}]

let%expect_test _ =
  parse_and_print "1.1.1-X";
  [%expect {| 1.1.1 [X] [] |}]

let%expect_test _ =
  parse_and_print "1.1.1-X+x";
  [%expect {| 1.1.1 [X] [x] |}]

let%expect_test _ =
  parse_and_print "1.1.1-aX+bX";
  [%expect {| 1.1.1 [aX] [bX] |}]

let%expect_test _ =
  parse_and_print "1.1.1-Xa+Xb";
  [%expect {| 1.1.1 [Xa] [Xb] |}]

let%expect_test _ =
  parse_and_print "1.1.1-X+x.x";
  [%expect {| 1.1.1 [X] [x;x] |}]
