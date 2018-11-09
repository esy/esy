(**
 * A parser of a subset of lockfile syntax enough to parse .esyrc.
 *)

include Types

let tokenize v =
  let lexbuf = Lexing.from_string v in
  let rec dedent tokens till indents =
    match indents with
    | [] -> 0, [], tokens
    | indent::indents ->
      if indent <= till then indent, indents, tokens
      else dedent (DEDENT::tokens) till indents
  in
  let rec loop (indent, indents) tokens =
    match Lexer.read lexbuf with
    | EOF ->
      let _, _, tokens = dedent tokens 0 (indent::indents) in
      List.rev (EOF::tokens)
    | NEWLINE nextIndent as token ->
      let indent, indents, tokens =
        if nextIndent > indent
        then nextIndent, (indent::indents), (INDENT::tokens)
        else if nextIndent < indent
        then
          let indent, indents, tokens = dedent tokens nextIndent (indent::indents) in
          indent, indents, token::tokens
        else indent, indents, token::tokens
      in
      loop (indent, indents) tokens
    | token ->
      loop (indent, indents) (token::tokens)
  in
  loop (0, []) []

let parse src =
  let open Result.Syntax in
  let src = String.trim src in
  let rtokens = ref (tokenize src) in
  let getToken _lexbuf =
    match !rtokens with
    | token::tokens ->
      rtokens := tokens;
      token
    | [] -> Types.EOF
  in
  let lexbuf = Lexing.from_string src in
  try
    return (Parser.start getToken lexbuf)
  with
  | Failure v ->
    error v
  | Parser.Error ->
    error "Syntax error"
  | Types.SyntaxError msg ->
    error msg

let parseExn src =
  match parse src with
  | Ok v -> v
  | Error err -> raise (SyntaxError err)

let%test_module "tokenizing" = (module struct

  let printTokens string =
    let tokens = tokenize (String.trim string) in
    let tokens = List.map ~f:Types.sexp_of_token tokens in
    Format.printf "%a@." (Fmt.list ~sep:(Fmt.unit "@.") Sexplib0.Sexp.pp) tokens

  let%expect_test _ =
    printTokens {|a: "b"|};
    [%expect {|
      (IDENTIFIER a)
      COLON
      (STRING b)
      EOF |}]

  let%expect_test _ =
    printTokens {|
      a: "b"
    |};
    [%expect {|
      (IDENTIFIER a)
      COLON
      (STRING b)
      EOF |}]

  let%expect_test _ =
    printTokens {|
      a:
        b: "x"
          c: "y"
        c: "y"
    |};
    [%expect {|
      (IDENTIFIER a)
      COLON
      INDENT
      (IDENTIFIER b)
      COLON
      (STRING x)
      INDENT
      (IDENTIFIER c)
      COLON
      (STRING y)
      DEDENT
      (NEWLINE 9)
      (IDENTIFIER c)
      COLON
      (STRING y)
      DEDENT
      EOF |}]

  let%expect_test _ =
    printTokens {|
      a:
        b: "x"
      c: "y"
    |};
    [%expect {|
      (IDENTIFIER a)
      COLON
      INDENT
      (IDENTIFIER b)
      COLON
      (STRING x)
      DEDENT
      (NEWLINE 7)
      (IDENTIFIER c)
      COLON
      (STRING y)
      EOF |}]

  let%expect_test _ =
    printTokens {|
a: b
c: d
    |};
    [%expect {|
      (IDENTIFIER a)
      COLON
      (IDENTIFIER b)
      (NEWLINE 0)
      (IDENTIFIER c)
      COLON
      (IDENTIFIER d)
      EOF |}]

  let%expect_test _ =
    printTokens {|
a:
  c: d
    |};
    [%expect {|
      (IDENTIFIER a)
      COLON
      INDENT
      (IDENTIFIER c)
      COLON
      (IDENTIFIER d)
      DEDENT
      EOF |}]

  let%expect_test _ =
    printTokens {|
a:
  c: d
    |};
    [%expect {|
      (IDENTIFIER a)
      COLON
      INDENT
      (IDENTIFIER c)
      COLON
      (IDENTIFIER d)
      DEDENT
      EOF |}]

  let%expect_test _ =
    printTokens {|
a:
  c: d
e: f
    |};
    [%expect {|
      (IDENTIFIER a)
      COLON
      INDENT
      (IDENTIFIER c)
      COLON
      (IDENTIFIER d)
      DEDENT
      (NEWLINE 0)
      (IDENTIFIER e)
      COLON
      (IDENTIFIER f)
      EOF |}]

end)

let%test_module _ = (module struct

  let printAst s =
    match parse s with
    | Ok s -> Format.printf "%a@." Sexplib0.Sexp.pp_hum (sexp_of_t s)
    | Error err -> Format.printf "ERROR: %s@." err

  let%expect_test "empty" =
    printAst "";
    [%expect {| (Mapping ()) |}]

  let%expect_test "empty with newline" =
    printAst "\n";
    [%expect {| (Mapping ()) |}]

  let%expect_test "id:true" =
    printAst "id:true";
    [%expect {| (Mapping ((id (Boolean true)))) |}]

  let%expect_test "id: true" =
    printAst "id: true";
    [%expect {| (Mapping ((id (Boolean true)))) |}]

  let%expect_test "id :true" =
    printAst "id :true";
    [%expect {| (Mapping ((id (Boolean true)))) |}]

  let%expect_test " id:true" =
    printAst " id:true";
    [%expect {| (Mapping ((id (Boolean true)))) |}]

  let%expect_test "id:true " =
    printAst "id:true ";
    [%expect {| (Mapping ((id (Boolean true)))) |}]

  let%expect_test "id: false" =
    printAst "id: false";
    [%expect {| (Mapping ((id (Boolean false)))) |}]

  let%expect_test "id: id" =
    printAst "id: id";
    [%expect {| (Mapping ((id (String id)))) |}]

  let%expect_test "id: string" =
    printAst {|id: "string"|};
    [%expect {| (Mapping ((id (String string)))) |}]

  let%expect_test "id: 1" =
    printAst "id: 1";
    [%expect {| (Mapping ((id (Number 1)))) |}]

  let%expect_test "id: 1.5" =
    printAst "id: 1.5";
    [%expect {| (Mapping ((id (Number 1.5)))) |}]

  let%expect_test "\"string\": ok" =
    printAst "\"string\": ok";
    [%expect {| (Mapping ((string (String ok)))) |}]

  let%expect_test "a:b\nc:d" =
    printAst "a:b\nc:d";
    [%expect {| (Mapping ((a (String b)) (c (String d)))) |}]

  let%expect_test "a:b\n" =
    printAst "a:b\n";
    [%expect {| (Mapping ((a (String b)))) |}]

  let%expect_test "\na:b" =
    printAst "\na:b";
    [%expect {| (Mapping ((a (String b)))) |}]

  let%expect_test "esy-store-path: \"/some/path\"" =
    printAst "esy-store-path: \"/some/path\"";
    [%expect {| (Mapping ((esy-store-path (String /some/path)))) |}]

  let%expect_test "esy-store-path: \"./some/path\"" =
    printAst "esy-store-path: \"./some/path\"";
    [%expect {| (Mapping ((esy-store-path (String ./some/path)))) |}]

  let%expect_test "esy-store-path: ./some/path" =
    printAst "esy-store-path: ./some/path";
    [%expect {| (Mapping ((esy-store-path (String ./some/path)))) |}]

  let%expect_test _ =
    printAst {|
      a: b
    |};
    [%expect {| (Mapping ((a (String b)))) |}]

  let%expect_test _ =
    printAst {|
a: b
c: d
    |};
    [%expect {| (Mapping ((a (String b)) (c (String d)))) |}]

  let%expect_test _ =
    printAst {|
a:
  c: d
    |};
    [%expect {| (Mapping ((a (Mapping ((c (String d))))))) |}]

  let%expect_test _ =
    printAst {|
a:
  c: d
  e: f
    |};
    [%expect {| (Mapping ((a (Mapping ((c (String d)) (e (String f))))))) |}]

  let%expect_test _ =
    printAst {|
a:
  c: d
e: f
    |};
    [%expect {| (Mapping ((a (Mapping ((c (String d))))) (e (String f)))) |}]

  let%expect_test _ =
    printAst {|
a:
  c:
    e: f
    |};
    [%expect {| (Mapping ((a (Mapping ((c (Mapping ((e (String f)))))))))) |}]

  let%expect_test _ =
    printAst {|
a:
  c:
    e:
      g: h
  x: y
    |};
    [%expect {|
      (Mapping
       ((a
         (Mapping ((c (Mapping ((e (Mapping ((g (String h)))))))) (x (String y))))))) |}]

  let%expect_test _ =
    printAst {|
a:
  c:
    e:
      g: h
x: y
    |};
    [%expect {|
      (Mapping
       ((a (Mapping ((c (Mapping ((e (Mapping ((g (String h)))))))))))
        (x (String y)))) |}]

  let%expect_test _ =
    printAst {|
a:
  1
  2
    |};
    [%expect {|
      (Mapping ((a (Sequence ((Number 1) (Number 2)))))) |}]

  let%expect_test _ =
    printAst {|
a:
  2
    |};
    [%expect {|
      (Mapping ((a (Sequence ((Number 2)))))) |}]

  let%expect_test _ =
    printAst {|
a:
  a
  b
  c
    |};
    [%expect {|
      (Mapping ((a (Sequence ((String a) (String b) (String c)))))) |}]

end)
