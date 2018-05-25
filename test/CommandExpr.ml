open Esy.CommandExpr
open Esy.CommandExpr.Expr

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
    let msg = Printf.sprintf "parse error: %s" (EsyLib.Run.formatError err) in
    print_endline msg;
    false

let%test "parse just string" =
  expectParseOk "something" (String "something")

let%test "parse just string w/ leading space" =
  expectParseOk " something" (String " something")

let%test "parse just string w/ trailing space" =
  expectParseOk "something " (String "something ")

let%test "string with squote" =
  expectParseOk "somet'ok'hing" (String "somet'ok'hing") &&
  expectParseOk "somet'ok' hing" (String "somet'ok' hing") &&
  expectParseOk "somet 'ok'hing" (String "somet 'ok'hing")

let%test "string with dquote" =
  expectParseOk "somet\"ok\"hing" (String "somet\"ok\"hing") &&
  expectParseOk "somet\"ok\" hing" (String "somet\"ok\" hing") &&
  expectParseOk "somet \"ok\"hing" (String "somet \"ok\"hing")

let%test "parse simple var" =
  expectParseOk "#{hi}" (Var ["hi"]) &&
  expectParseOk "#{hi }" (Var ["hi"]) &&
  expectParseOk "#{ hi}" (Var ["hi"])

let%test "parse var+" =
  expectParseOk "#{hi}#{world}" (Concat [
    Var ["hi"];
    Var ["world"]
    ])

let%test "parse string + var" =
  expectParseOk "hello #{world}" (Concat [String "hello "; Var ["world"]]) &&
  expectParseOk " #{world}" (Concat [String " "; Var ["world"]]) &&
  expectParseOk "#{world} " (Concat [Var ["world"]; String " "]) &&
  expectParseOk "hello#{world}" (Concat [String "hello"; Var ["world"]]) &&
  expectParseOk "#{hello} world" (Concat [Var ["hello"]; String " world"]) &&
  expectParseOk "#{hello}world" (Concat [Var ["hello"]; String "world"])

let%test "parse complex var" =
  expectParseOk "#{hi world}" (Concat [Var ["hi"]; Var ["world"]])
  && expectParseOk "#{h-i world}" (Concat [Var ["h-i"]; Var ["world"]])
  && expectParseOk "#{hi :}" (Concat [Var ["hi"]; Colon])
  && expectParseOk "#{hi : world}" (Concat [Var ["hi"]; Colon; Var ["world"]])
  && expectParseOk "#{hi /}" (Concat [Var ["hi"]; PathSep])
  && expectParseOk "#{hi / world}" (Concat [Var ["hi"]; PathSep; Var ["world"]])

let%test "parse var with env vars" =
  expectParseOk "#{hi / $world}" (Concat [Var ["hi"]; PathSep; EnvVar "world"])

let%test "parse var with literals" =
  expectParseOk "#{'world'}" (String "world")
  && expectParseOk "#{/ 'world'}" (Concat [PathSep; String "world"])
  && expectParseOk "#{: 'world'}" (Concat [Colon; String "world"])
  && expectParseOk "#{/'world'}" (Concat [PathSep; String "world"])
  && expectParseOk "#{:'world'}" (Concat [Colon; String "world"])
  && expectParseOk "#{'world' /}" (Concat [String "world"; PathSep])
  && expectParseOk "#{'world' :}" (Concat [String "world"; Colon])
  && expectParseOk "#{'world'/}" (Concat [String "world"; PathSep])
  && expectParseOk "#{'world':}" (Concat [String "world"; Colon])
  && expectParseOk "#{hi'world'}" (Concat [Var ["hi"]; String "world"])
  && expectParseOk "#{'world'hi}" (Concat [String "world"; Var ["hi"]])
  && expectParseOk "#{hi / 'world'}" (Concat [Var ["hi"]; PathSep; String "world"])
  && expectParseOk "#{'hi''world'}" (Concat [String "hi";  String "world"])
  && expectParseOk "#{'h\\'i'}" (String "h'i")

let%test "parse namespace" =
  expectParseOk "#{ns.hi}" (Var ["ns"; "hi"])
  && expectParseOk "#{n-s.hi}" (Var ["n-s"; "hi"])
  && expectParseOk "#{ns.hi.hey}" (Var ["ns"; "hi"; "hey"])
  && expectParseOk "#{@scope/pkg.hi}" (Var ["@scope/pkg"; "hi"])
  && expectParseOk "#{@s-cope/pkg.hi}" (Var ["@s-cope/pkg"; "hi"])
  && expectParseOk "#{@scope/pkg.hi.hey}" (Var ["@scope/pkg"; "hi"; "hey"])
  && expectParseOk "#{@scope/pkg.hi 'hey'}" (Concat [
    Var ["@scope/pkg"; "hi"];
    String ("hey");
  ])

let%test "parse conditionals (strings in then / else)" =
  expectParseOk
    "#{lwt.installed ? '--enable-lwt' : '--disable-lwt'}"
    (Condition (
      (Var ["lwt"; "installed"]),
      (String "--enable-lwt"),
      (String "--disable-lwt")
      ))

let%test "parse conditionals (vars in then / else)" =
  expectParseOk
    "#{lwt.installed ? then : else}"
    (Condition (
      (Var ["lwt"; "installed"]),
      (Var ["then"]),
      (Var ["else"])
      ))

let%test "parse conditionals (lists in then / else)" =
  expectParseOk
    "#{lwt.installed ? (then : then) : (else : else)}"
    (Condition (
      (Var ["lwt"; "installed"]),
      (Concat [Var ["then"]; Colon; Var ["then"]]),
      (Concat [Var ["else"]; Colon; Var ["else"]])
      ))

let%test "parse conj" =
  expectParseOk
    "#{lwt.installed && async.installed}"
    (And (
      (Var ["lwt"; "installed"]),
      (Var ["async"; "installed"])
      ))

let expectRenderOk scope s expected =
  match render ~scope s with
  | Ok v ->
    if v <> expected then (
      Printf.printf "Expected: %s\n" expected;
      Printf.printf "     Got: %s\n" v;
      false
    ) else
      true
  | Error err ->
    let msg = Printf.sprintf "error: %s" (EsyLib.Run.formatError err) in
    print_endline msg;
    false

let expectRenderError scope s expectedError =
  match render ~scope s with
  | Ok _ -> false
  | Error error ->
    let error = EsyLib.Run.formatError error in
    if expectedError <> error then (
      Printf.printf "Expected: %s\n" expectedError;
      Printf.printf "     Got: %s\n" error;
      false
    ) else true

let scope = function
| "name"::[] -> Some (Value.String "pkg")
| "isTrue"::[] -> Some (Value.Bool true)
| "isFalse"::[] -> Some (Value.Bool false)
| "self"::"lib"::[] -> Some (Value.String "store/lib")
| _ -> None

let%test "render" =

  expectRenderOk scope "Hello, #{name}!" "Hello, pkg!"
  && expectRenderOk scope "#{self.lib / $NAME}" "store/lib/$NAME"
  && expectRenderError scope "#{unknown}" "Error: Undefined variable 'unknown'"
  && expectRenderError scope "#{ns.unknown}" "Error: Undefined variable 'ns.unknown'"
  && expectRenderOk scope "#{isTrue ? 'ok' : 'oops'}" "ok"
  && expectRenderOk scope "#{isFalse ? 'oops' : 'ok'}" "ok"
  && expectRenderOk scope "#{isFalse && isTrue ? 'oops' : 'ok'}" "ok"
