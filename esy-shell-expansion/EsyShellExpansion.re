include Types;

let formatParseError = (~src=?, ~cnum, msg) =>
  switch (src) {
  | None => msg
  | Some(src) =>
    let ctx = {
      let cnum = min(String.length(src), cnum + 5);
      String.sub(src, 0, cnum) ++ "...";
    };

    let line =
      String.init(String.length(ctx), i =>
        if (i == cnum) {
          '^';
        } else {
          ' ';
        }
      );

    Printf.sprintf("%s:\n>\n> %s\n> %s", msg, ctx, line);
  };

let parseExn = v => {
  let lexbuf = Lexing.from_string(v);
  Lexer.read([], `Init, lexbuf);
};

let parse = src =>
  try(Ok(parseExn(src))) {
  | [@implicit_arity] UnmatchedChar(pos, _) =>
    let cnum = pos.Lexing.pos_cnum - 1;
    let msg = formatParseError(~src, ~cnum, "unknown character");
    Error(msg);
  | [@implicit_arity] UnknownShellEscape(pos, str) =>
    let cnum = pos.Lexing.pos_cnum - String.length(str);
    let msg = formatParseError(~src, ~cnum, "unknown shell escape sequence");
    Error(msg);
  };

type scope = string => option(string);

let render = (~fallback=Some(""), ~scope: scope, v) => {
  let rec renderTokens = (segments, tokens) =>
    switch (tokens) {
    | [] => Ok(String.concat("", List.rev(segments)))
    | [String(v), ...restTokens] =>
      renderTokens([v, ...segments], restTokens)
    | [[@implicit_arity] Var(name, default), ...restTokens] =>
      switch (scope(name), default, fallback) {
      | (Some(v), _, _)
      | (None, Some(v), _) => renderTokens([v, ...segments], restTokens)
      | (None, None, Some(v)) => renderTokens([v, ...segments], restTokens)
      | (_, _, _) => Error("unable to resolve: $" ++ name)
      }
    };

  switch (parse(v)) {
  | Error(err) => Error(err)
  | Ok(tokens) => renderTokens([], tokens)
  };
};

let%test_module _ =
  (module
   {
     let expectParseOk = (s, expectedTokens) =>
       switch (parse(s)) {
       | Ok(tokens) =>
         if (!equal(tokens, expectedTokens)) {
           Printf.printf("Expected: %s\n", show(expectedTokens));
           Printf.printf("     Got: %s\n", show(tokens));
           false;
         } else {
           true;
         }
       | Error(err) =>
         let msg = Printf.sprintf("Error: %s\nWhile parsing: %s", err, s);
         print_endline(msg);
         false;
       };

     let%test "string" =
       expectParseOk("string", [String("string")])
       && expectParseOk("just string", [String("just string")]);

     let%test "$var" =
       expectParseOk("$var", [[@implicit_arity] Var("var", None)])
       && expectParseOk(
            "$var string",
            [[@implicit_arity] Var("var", None), String(" string")],
          )
       && expectParseOk(
            "string $var",
            [String("string "), [@implicit_arity] Var("var", None)],
          );

     let%test "${var}" =
       expectParseOk("${var}", [[@implicit_arity] Var("var", None)])
       && expectParseOk(
            "${var} string",
            [[@implicit_arity] Var("var", None), String(" string")],
          )
       && expectParseOk(
            "string ${var}",
            [String("string "), [@implicit_arity] Var("var", None)],
          )
       && expectParseOk(
            "${var}string",
            [[@implicit_arity] Var("var", None), String("string")],
          )
       && expectParseOk(
            "string${var}",
            [String("string"), [@implicit_arity] Var("var", None)],
          );

     let%test "${var:-default}" =
       expectParseOk(
         "${var:-def}",
         [[@implicit_arity] Var("var", Some("def"))],
       )
       && expectParseOk(
            "${var:-def} string",
            [[@implicit_arity] Var("var", Some("def")), String(" string")],
          )
       && expectParseOk(
            "string ${var:-def}",
            [String("string "), [@implicit_arity] Var("var", Some("def"))],
          )
       && expectParseOk(
            "${var:-def}string",
            [[@implicit_arity] Var("var", Some("def")), String("string")],
          )
       && expectParseOk(
            "string${var:-def}",
            [String("string"), [@implicit_arity] Var("var", Some("def"))],
          );

     let expectRenderOk = (scope, s, expectedResult) =>
       switch (render(~scope, s)) {
       | Ok(result) =>
         if (result != expectedResult) {
           Printf.printf("Expected: %s\n", expectedResult);
           Printf.printf("     Got: %s\n", result);
           false;
         } else {
           true;
         }
       | Error(err) =>
         let msg = Printf.sprintf("Error: %s\nWhile parsing: %s", err, s);
         print_endline(msg);
         false;
       };

     let%test "render" = {
       let scope =
         fun
         | "name" => Some("world")
         | _ => None;

       expectRenderOk(scope, "hello", "hello")
       && expectRenderOk(scope, "hello, $name", "hello, world")
       && expectRenderOk(scope, "hello, ${name}!", "hello, world!")
       && expectRenderOk(scope, "hello, ${nam:-world}!", "hello, world!");
     };
   });
