open Ppx_sexp_conv_lib.Conv

type prerelease_id = Types.prerelease_id =
  | N of int
  | A of string
  [@@deriving sexp]

type t = Types.version = {
  major : int;
  minor : int;
  patch : int;
  prerelease : prerelease_id list;
  build : string list;
}
[@@deriving sexp]

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
  match Parser.parse_version Lexer.version lexbuf with
  | exception Lexer.Error msg -> Error msg
  | exception Parser.Error ->
    let pos = lexbuf.Lexing.lex_curr_p.pos_cnum in
    let msg = Printf.sprintf "error parsing: %i column" pos in
    Error msg
  | v -> Ok v

let parse_and_print v =
  match parse v with
  | Ok v ->
    Format.printf "OK: %a" Sexplib0.Sexp.pp_hum (sexp_of_t v)
  | Error msg ->
    Format.printf "ERROR: %s" msg

let%expect_test _ =
  parse_and_print "1.1.1";
  [%expect {|
    OK: ((major 1) (minor 1) (patch 1) (prerelease ()) (build ()))
  |}]

let%expect_test _ =
  parse_and_print "1.1.1-1";
  [%expect {|
    OK: ((major 1) (minor 1) (patch 1) (prerelease ((N 1))) (build ())) |}]

let%expect_test _ =
  parse_and_print "1.1.1-12.2";
  [%expect {|
    OK: ((major 1) (minor 1) (patch 1) (prerelease ((N 12) (N 2))) (build ())) |}]

let%expect_test _ =
  parse_and_print "1.1.1+build";
  [%expect {|
    OK: ((major 1) (minor 1) (patch 1) (prerelease ()) (build (build))) |}]

let%expect_test _ =
  parse_and_print "1.1.1+build.another";
  [%expect {|
    OK: ((major 1) (minor 1) (patch 1) (prerelease ()) (build (build another))) |}]

let%expect_test _ =
  parse_and_print "1.1.1-release+build";
  [%expect {|
    OK: ((major 1) (minor 1) (patch 1) (prerelease ((A release)))
         (build (build))) |}]

let%expect_test _ =
  parse_and_print "1.1.1-rel-2020";
  [%expect {|
    OK: ((major 1) (minor 1) (patch 1) (prerelease ((A rel-2020))) (build ())) |}]

let%expect_test _ =
  parse_and_print "1.1.1-rel-2020-05.12";
  [%expect {|
    OK: ((major 1) (minor 1) (patch 1) (prerelease ((A rel-2020-05) (N 12)))
         (build ())) |}]

let%expect_test _ =
  parse_and_print "1.1.1-rel-2020+build-2020";
  [%expect {|
    OK: ((major 1) (minor 1) (patch 1) (prerelease ((A rel-2020)))
         (build (build-2020))) |}]

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

let show v =
  Format.asprintf "%a" pp v
