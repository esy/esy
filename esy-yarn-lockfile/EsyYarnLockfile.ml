(**
 * A parser of a subset of lockfile syntax enough to parse .esyrc.
 *)

include Types

(* TODO: this should really be lazy but we don't care as we don't expect .esyrc
 * to be large, make it lazy when we are going to use it for large inputs like
 * .esy.lock files.
 *)
let tokensOf v =
  let lexbuf = Lexing.from_string v in
  let rec loop ~acc = function
  | EOF -> List.rev (EOF::acc)
  | x ->  loop ~acc:(x::acc) (Lexer.read lexbuf)
  in
  loop ~acc:[] (Lexer.read lexbuf)

type parseState =
  | InMapping of { items : (string * t) list }
  | InValue of { key : string; items : (string * t) list }

let parseExn v =
  let tokens = tokensOf v in
  let rec loop state tokens = match state, tokens with
  | InMapping {items}, EOF::[] -> Mapping items
  | InMapping {items}, (STRING v)::tokens
  | InMapping {items}, (IDENTIFIER v)::tokens -> loop (InValue { key = v; items = items }) tokens
  | InMapping _, (NEWLINE)::tokens -> loop state tokens
  | InMapping _, (EOF::_) -> raise (SyntaxError "tokens after EOF")
  | InMapping _, (NUMBER _)::_ -> raise (SyntaxError "expected newline or string, got number")
  | InMapping _, (FALSE)::_ -> raise (SyntaxError "expected newline or string, got boolean")
  | InMapping _, (TRUE)::_ -> raise (SyntaxError "expected newline or string, got boolean")
  | InMapping _, (COLON)::_ -> raise (SyntaxError "expected newline or string, got colon")
  | InValue _, [] -> raise (SyntaxError "expected value, got EOF")
  | InValue _, EOF::_ -> raise (SyntaxError "expected value, got EOF")
  | InValue _, (COLON)::tokens -> loop state tokens
  | InValue _, (NEWLINE)::tokens -> loop state tokens
  | InValue {key; items}, (NUMBER v)::tokens ->
    let item = (key, Number v) in
    loop (InMapping { items = List.rev (item::items) }) tokens
  | InValue {key; items}, (FALSE)::tokens ->
    let item = (key, Boolean false) in
    loop (InMapping { items = List.rev (item::items) }) tokens
  | InValue {key; items}, (TRUE)::tokens ->
    let item = (key, Boolean true) in
    loop (InMapping { items = List.rev (item::items) }) tokens
  | InValue {key; items}, (STRING v)::tokens
  | InValue {key; items}, (IDENTIFIER v)::tokens ->
    let item = (key, String v) in
    loop (InMapping { items = List.rev (item::items) }) tokens
  | _state, (COMMA)::_tokens -> raise (SyntaxError "syntax is not supported")
  | _, [] -> failwith "token stream does not end with EOF"
  in loop (InMapping { items = [] }) tokens

let parse v =
  try Ok (parseExn v)
  with SyntaxError err -> Error err

let%test_module _ = (module struct
  let expectParseOk s expectedTokens =
    match parse s with
    | Ok tokens ->
      if not (equal tokens expectedTokens) then (
        Printf.printf "Expected: %s\n" (show expectedTokens);
        Printf.printf "     Got: %s\n" (show tokens);
        false
      ) else
        true
    | Error err ->
      let msg = Printf.sprintf "parse error: %s" err in
      print_endline msg;
      false

  let%test "empty" =
    expectParseOk "" (Mapping [])

  let%test "empty with newline" =
    expectParseOk "\n" (Mapping [])

  let%test "id:true" =
    expectParseOk "id:true" (Mapping [("id", Boolean true)])

  let%test "id: true" =
    expectParseOk "id: true" (Mapping [("id", Boolean true)])

  let%test "id :true" =
    expectParseOk "id :true" (Mapping [("id", Boolean true)])

  let%test " id:true" =
    expectParseOk " id:true" (Mapping [("id", Boolean true)])

  let%test "id:true " =
    expectParseOk "id:true " (Mapping [("id", Boolean true)])

  let%test "id: false" =
    expectParseOk "id: false" (Mapping [("id", Boolean false)])

  let%test "id: id" =
    expectParseOk "id: id" (Mapping [("id", String "id")])

  let%test "id: string" =
    expectParseOk "id: \"string\"" (Mapping [("id", String "string")])

  let%test "id: 1" =
    expectParseOk "id: 1" (Mapping [("id", Number 1.)])

  let%test "id: 1.5" =
    expectParseOk "id: 1.5" (Mapping [("id", Number 1.5)])

  let%test "\"string\": ok" =
    expectParseOk "\"string\": ok" (Mapping [("string", String "ok")])

  let%test "a:b\nc:d" =
    expectParseOk "a:b\nc:d" (Mapping [("a", String "b"); ("c", String "d")])

  let%test "a:b\n" =
    expectParseOk "a:b\n" (Mapping [("a", String "b")])

  let%test "\na:b" =
    expectParseOk "\na:b" (Mapping [("a", String "b")])

  let%test "esy-store-path: \"/some/path\"" =
    expectParseOk "esy-store-path: \"/some/path\"" (Mapping [("esy-store-path", String "/some/path")])

  let%test "esy-store-path: \"./some/path\"" =
    expectParseOk "esy-store-path: \"./some/path\"" (Mapping [("esy-store-path", String "./some/path")])

  let%test "esy-store-path: ./some/path" =
    expectParseOk "esy-store-path: ./some/path" (Mapping [("esy-store-path", String "./some/path")])
end)
