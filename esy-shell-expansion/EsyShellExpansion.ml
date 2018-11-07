include Types

let formatParseError ?src ~cnum msg =
  match src with
  | None -> msg
  | Some src ->
    let ctx =
      let cnum = min (String.length src) (cnum + 5) in
      (String.sub src 0 cnum) ^ "..."
    in
    let line =
      String.init
        (String.length ctx)
        (fun i -> if i = cnum then '^' else ' ')
    in
    Printf.sprintf "%s:\n>\n> %s\n> %s" msg ctx line

let parseShellExn v =
  let lexbuf = Lexing.from_string v in
  Lexer.read [] `Init lexbuf

let parseBatchExn v =
  let lexbuf = Lexing.from_string v in
  BatchLexer.read [] `Init lexbuf

let parse parseExn src =
  try Ok (parseExn src)
  with
  | UnmatchedChar (pos, _) ->
    let cnum = pos.Lexing.pos_cnum - 1 in
    let msg = formatParseError ~src ~cnum "unknown character" in
    Error msg
  | UnknownShellEscape (pos, str) ->
    let cnum = pos.Lexing.pos_cnum - String.length str in
    let msg = formatParseError ~src ~cnum "unknown shell escape sequence" in
    Error msg

type scope = string -> string option

let render' ~(scope : scope) parseExn v =

  let rec renderTokens segments tokens =
    match tokens with
    | [] -> Ok (String.concat "" (List.rev segments))
    | String v::restTokens -> renderTokens (v::segments) restTokens
    | Var (name, default)::restTokens ->
      begin match scope name, default with
      | Some v, _
      | None, Some v -> renderTokens (v::segments) restTokens
      | _, _ -> Error ("unable to resolve: $" ^ name)
      end
  in

  match parse parseExn v with
  | Error err -> Error err
  | Ok tokens -> renderTokens [] tokens

let render ~scope v = render' ~scope parseShellExn v
let renderBatch ~scope v = render' ~scope parseBatchExn v

let%test_module _ = (module struct
  let expectParseOk s expectedTokens =
    match parse parseShellExn s with
    | Ok tokens ->
      if not (equal tokens expectedTokens) then (
        Printf.printf "Expected: %s\n" (show expectedTokens);
        Printf.printf "     Got: %s\n" (show tokens);
        false
      ) else
        true
    | Error err ->
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

  let expectRenderOk render scope s expectedResult =
    match render ~scope s with
    | Ok result ->
      if result <> expectedResult then (
        Printf.printf "Expected: %s\n" expectedResult;
        Printf.printf "     Got: %s\n" result;
        false
      ) else
        true
    | Error err ->
      let msg = Printf.sprintf "Error: %s\nWhile parsing: %s" err s in
      print_endline msg;
      false

  let%test "render" =
    let scope = function
      | "name" -> Some "world"
      | _ -> None
    in
    expectRenderOk render scope "hello" "hello" &&
    expectRenderOk render scope "hello, $name" "hello, world" &&
    expectRenderOk render scope "hello, ${name}!" "hello, world!" &&
    expectRenderOk render scope "hello, ${nam:-world}!" "hello, world!"

  let%test "render batch" =
    let scope = function
      | "name" -> Some "world"
      | _ -> None
    in
    expectRenderOk renderBatch scope "hello" "hello" &&
    expectRenderOk renderBatch scope "hello, %name%" "hello, world"
end)
