open Esy.LockfileParser

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
    let msg = Printf.sprintf "parse error: %s" (Esy.Run.formatError err) in
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
