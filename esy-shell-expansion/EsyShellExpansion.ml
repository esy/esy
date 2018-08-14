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

let parseExn v =
  let lexbuf = Lexing.from_string v in
  Lexer.read [] `Init lexbuf

let parse src =
  let open Result.Syntax in
  try return (parseExn src)
  with
  | UnmatchedChar (pos, _) ->
    let cnum = pos.Lexing.pos_cnum - 1 in
    let msg = formatParseError ~src ~cnum "unknown character" in
    error msg
  | UnknownShellEscape (pos, str) ->
    let cnum = pos.Lexing.pos_cnum - String.length str in
    let msg = formatParseError ~src ~cnum "unknown shell escape sequence" in
    error msg

type scope = string -> string option

let render ?(fallback=Some "") ~(scope : scope) v =
  let open Result.Syntax in
  let%bind tokens = parse v in
  let f segments = function
    | String v -> return (v::segments)
    | Var (name, default) ->
      begin match scope name, default, fallback with
      | Some v, _, _
      | None, Some v, _ -> return (v::segments)
      | None, None, Some v -> return (v::segments)
      | _, _, _ -> error ("unable to resolve: $" ^ name)
      end
  in
  let%bind segments = Result.List.foldLeft ~f ~init:[] tokens in
  return (segments |> List.rev |> String.concat "")

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
end)
