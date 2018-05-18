include Esy.ShellParamExpansion

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
    let err = EsyLib.Run.formatError err in
    let msg = Printf.sprintf "Error: %s\nWhile parsing: %s" err s in
    print_endline msg;
    false

let%test "string" =
  expectParseOk "string" [String "string"] &&
  expectParseOk "just string" [String "just string"]

let%test "$var" =
  expectParseOk "$var" [Var ("var", None)] &&
  expectParseOk "$var string" [Var ("var", None); String " string"] &&
  expectParseOk "string $var" [String "string "; Var ("var", None)]

let%test "${var}" =
  expectParseOk "${var}" [Var ("var", None)] &&
  expectParseOk "${var} string" [Var ("var", None); String " string"] &&
  expectParseOk "string ${var}" [String "string "; Var ("var", None)] &&
  expectParseOk "${var}string" [Var ("var", None); String "string"] &&
  expectParseOk "string${var}" [String "string"; Var ("var", None)]

let%test "${var:-default}" =
  expectParseOk "${var:-def}" [Var ("var", Some "def")] &&
  expectParseOk "${var:-def} string" [Var ("var", Some "def"); String " string"] &&
  expectParseOk "string ${var:-def}" [String "string "; Var ("var", Some "def")] &&
  expectParseOk "${var:-def}string" [Var ("var", Some "def"); String "string"] &&
  expectParseOk "string${var:-def}" [String "string"; Var ("var", Some "def")]

let expectRenderOk scope s expectedResult =
  match render ~scope s with
  | Ok result ->
    if result <> expectedResult then (
      Printf.printf "Expected: %s\n" expectedResult;
      Printf.printf "     Got: %s\n" result;
      false
    ) else
      true
  | Error err ->
    let err = EsyLib.Run.formatError err in
    let msg = Printf.sprintf "Error: %s\nWhile parsing: %s" err s in
    print_endline msg;
    false

let%test "render" =
  let scope = function
    | "name" -> Some "world"
    | _ -> None
  in
  expectRenderOk scope "hello" "hello" &&
  expectRenderOk scope "hello, $name" "hello, world" &&
  expectRenderOk scope "hello, ${name}!" "hello, world!" &&
  expectRenderOk scope "hello, ${nam:-world}!" "hello, world!"
