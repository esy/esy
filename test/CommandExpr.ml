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
  expectParseOk "#{hi}" (Var (None, "hi")) &&
  expectParseOk "#{hi }" (Var (None, "hi")) &&
  expectParseOk "#{ hi}" (Var (None, "hi"))

let%test "parse var+" =
  expectParseOk "#{hi}#{world}" (Concat [
    Var (None, "hi");
    Var (None, "world")
    ])

let%test "parse string + var" =
  expectParseOk "hello #{world}" (Concat [String "hello "; Var (None, "world")]) &&
  expectParseOk " #{world}" (Concat [String " "; Var (None, "world")]) &&
  expectParseOk "#{world} " (Concat [Var (None, "world"); String " "]) &&
  expectParseOk "hello#{world}" (Concat [String "hello"; Var (None, "world")]) &&
  expectParseOk "#{hello} world" (Concat [Var (None, "hello"); String " world"]) &&
  expectParseOk "#{hello}world" (Concat [Var (None, "hello"); String "world"])

let%test "parse complex var" =
  expectParseOk "#{hi world}" (Concat [Var (None, "hi"); Var (None, "world")])
  && expectParseOk "#{h-i world}" (Concat [Var (None, "h-i"); Var (None, "world")])
  && expectParseOk "#{hi :}" (Concat [Var (None, "hi"); Colon])
  && expectParseOk "#{hi : world}" (Concat [Var (None, "hi"); Colon; Var (None, "world")])
  && expectParseOk "#{hi /}" (Concat [Var (None, "hi"); PathSep])
  && expectParseOk "#{hi / world}" (Concat [Var (None, "hi"); PathSep; Var (None, "world")])

let%test "parse var with env vars" =
  expectParseOk "#{hi / $world}" (Concat [Var (None, "hi"); PathSep; EnvVar "world"])

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
  && expectParseOk "#{hi'world'}" (Concat [Var (None, "hi"); String "world"])
  && expectParseOk "#{'world'hi}" (Concat [String "world"; Var (None, "hi")])
  && expectParseOk "#{hi / 'world'}" (Concat [Var (None, "hi"); PathSep; String "world"])
  && expectParseOk "#{'hi''world'}" (Concat [String "hi";  String "world"])
  && expectParseOk "#{'h\\'i'}" (String "h'i")

let%test "parse namespace" =
  expectParseOk "#{ns.hi}" (Var (Some "ns", "hi"))
  && expectParseOk "#{n-s.hi}" (Var (Some "n-s", "hi"))
  && expectParseOk "#{@scope/pkg.hi}" (Var (Some "@scope/pkg", "hi"))
  && expectParseOk "#{@s-cope/pkg.hi}" (Var (Some "@s-cope/pkg", "hi"))
  && expectParseOk "#{@scope/pkg.hi 'hey'}" (Concat [
    Var (Some "@scope/pkg", "hi");
    String ("hey");
  ])

let%test "parse conditionals (strings in then / else)" =
  expectParseOk
    "#{lwt.installed ? '--enable-lwt' : '--disable-lwt'}"
    (Condition (
      (Var (Some "lwt", "installed")),
      (String "--enable-lwt"),
      (String "--disable-lwt")
      ))

let%test "parse conditionals (vars in then / else)" =
  expectParseOk
    "#{lwt.installed ? then : else}"
    (Condition (
      (Var (Some "lwt", "installed")),
      (Var (None, "then")),
      (Var (None, "else"))
      ))

let%test "parse conditionals (lists in then / else)" =
  expectParseOk
    "#{lwt.installed ? (then : then) : (else : else)}"
    (Condition (
      (Var (Some "lwt", "installed")),
      (Concat [Var (None, "then"); Colon; Var (None, "then")]),
      (Concat [Var (None, "else"); Colon; Var (None, "else")])
      ))

let%test "parse conj" =
  expectParseOk
    "#{lwt.installed && async.installed}"
    (And (
      (Var (Some "lwt", "installed")),
      (Var (Some "async", "installed"))
      ))

let%test "parse opam global" =
  expectParseOk
    "%{name}%"
    (OpamVar ([], "name"))
  && expectParseOk
    "%{name }%"
    (OpamVar ([], "name"))
  && expectParseOk
    "%{ name}%"
    (OpamVar ([], "name"))

let%test "parse opam with surroundings" =
  expectParseOk
    "%{name}%!"
    (Concat [OpamVar ([], "name"); String "!"])
  && expectParseOk
    "hey, %{name}%!"
    (Concat [String "hey, "; OpamVar ([], "name"); String "!"])

let%test "parse opam scoped" =
  expectParseOk
    "%{name:var}%"
    (OpamVar (["name"], "var"))
  && expectParseOk
    "%{name :var}%"
    (OpamVar (["name"], "var"))
  && expectParseOk
    "%{name: var}%"
    (OpamVar (["name"], "var"))

let%test "parse opam scoped with +" =
  expectParseOk
    "%{pkg1+pkg2:var}%"
    (OpamVar (["pkg1"; "pkg2"], "var"))
  && expectParseOk
    "%{pkg1 +pkg2:var}%"
    (OpamVar (["pkg1"; "pkg2"], "var"))
  && expectParseOk
    "%{pkg1+ pkg2:var}%"
    (OpamVar (["pkg1"; "pkg2"], "var"))

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
    let error = error |> EsyLib.Run.formatError |> String.trim in
    if (String.trim expectedError) <> error then (
      Printf.printf "Expected: %s\n" expectedError;
      Printf.printf "     Got: %s\n" error;
      false
    ) else true

let scope = function
| None, "name" -> Some (Value.String "pkg")
| None, "isTrue" -> Some (Value.Bool true)
| None, "isFalse" -> Some (Value.Bool false)
| None, "opam:os" -> Some (Value.String "MSDOS")
| Some "self", "lib" -> Some (Value.String "store/lib")
| Some "@opam/pkg", "lib" -> Some (Value.String "store/opam-pkg/lib")
| Some "@opam/pkg1", "installed" -> Some (Value.Bool true)
| Some "@opam/pkg2", "installed" -> Some (Value.Bool true)
| Some "@opam/pkg-not", "installed" -> Some (Value.Bool false)
| _ -> None

let%test "render" =

  expectRenderOk scope "Hello, #{name}!" "Hello, pkg!"
  && expectRenderOk scope "#{self.lib / $NAME}" "store/lib/$NAME"
  && expectRenderOk scope "#{isTrue ? 'ok' : 'oops'}" "ok"
  && expectRenderOk scope "#{isFalse ? 'oops' : 'ok'}" "ok"
  && expectRenderOk scope "#{isFalse && isTrue ? 'oops' : 'ok'}" "ok"


let%test "render opam" =
  expectRenderOk scope "Hello, %{os}%!" "Hello, MSDOS!"
  && expectRenderOk scope "%{pkg:lib}%" "store/opam-pkg/lib"
  && expectRenderOk scope "%{pkg1:enable}%" "enable"
  && expectRenderOk scope "%{pkg-not:enable}%" "disable"
  && expectRenderOk scope "%{pkg1+pkg2:enable}%" "enable"
  && expectRenderOk scope "%{pkg1+pkg-not:enable}%" "disable"
  && expectRenderOk scope "%{pkg1:installed}%" "true"
  && expectRenderOk scope "%{pkg-not:installed}%" "false"
  && expectRenderOk scope "%{pkg1+pkg2:installed}%" "true"
  && expectRenderOk scope "%{pkg1+pkg-not:installed}%" "false"

let%test "render errors" =
  expectRenderError scope "#{unknown}" "Error: Undefined variable 'unknown'"
  && expectRenderError scope "#{ns.unknown}" "Error: Undefined variable 'ns.unknown'"
  && expectRenderError scope "#{ns.unknown" "Error: unexpected end of string:
>
> #{ns.unknown...
>            ^"
  && expectRenderError scope "#{'some" "Error: unexpected end of string:
>
> #{'some...
>       ^"
  && expectRenderError scope "#{'some}" "Error: unexpected end of string:
>
> #{'some}...
>        ^"
  && expectRenderError scope "#{cond ^}" "Error: unexpected token '^' found:
>
> #{cond ^}...
>        ^"

let%test "syntax errors" =
  expectRenderError scope "#{cond &&}" "Error: Syntax error"
  && expectRenderError scope "#{cond ?}" "Error: Syntax error"
  && expectRenderError scope "#{cond ? then}" "Error: Syntax error"
  && expectRenderError scope "#{cond ? then :}" "Error: Syntax error"
