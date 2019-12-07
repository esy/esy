module V = Types.Value;
module E = Types.Expr;

module Value = Types.Value;

type scope = Types.scope;

let bool = v => V.Bool(v);
let string = v => V.String(v);

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

let parse = src => {
  let tokensStore = ref(None);
  let getToken = lexbuf => {
    let tokens =
      switch (tokensStore^) {
      | Some(tokens) => tokens
      | None => Lexer.read([], lexbuf)
      };

    switch (tokens) {
    | [tok, ...rest] =>
      tokensStore := Some(rest);
      tok;
    | [] => Parser.EOF
    };
  };

  let lexbuf = Lexing.from_string(src);
  Result.Syntax.(
    try(return(Parser.start(getToken, lexbuf))) {
    | Failure(v) => error(v)
    | Parser.Error => error("Syntax error")
    | [@implicit_arity] Lexer.Error(pos, msg) =>
      let cnum = pos.Lexing.pos_cnum - 1;
      let msg = formatParseError(~src, ~cnum, msg);
      error(msg);
    }
  );
};

let formatName =
  fun
  | (Some(namespace), name) => namespace ++ "." ++ name
  | (None, name) => name;

let eval = (~envVar, ~pathSep, ~colon, ~scope, string) => {
  open Result.Syntax;
  let%bind expr = parse(string);

  let lookupValue = name =>
    switch (scope(name)) {
    | Some(value) => return(value)
    | None =>
      let name = formatName(name);
      let msg = Printf.sprintf("Undefined variable '%s'", name);
      error(msg);
    };

  let rec evalToString = expr =>
    switch%bind (eval(expr)) {
    | V.String(v) => return(v)
    | V.Bool(true) => return("true")
    | V.Bool(false) => return("false")
    }
  and evalToBool = expr =>
    switch%bind (eval(expr)) {
    | V.Bool(v) => return(v)
    | V.String(_) => error("Expected bool but got string")
    }
  and eval =
    fun
    | E.String(s) => return(V.String(s))
    | E.Bool(b) => return(V.Bool(b))
    | E.PathSep => return(V.String(pathSep))
    | E.Colon => return(V.String(colon))
    | E.EnvVar(name) => envVar(name)
    | E.Var(name) => lookupValue(name)
    | [@implicit_arity] E.Condition(cond, t, e) =>
      if%bind (evalToBool(cond)) {
        eval(t);
      } else {
        eval(e);
      }
    | [@implicit_arity] E.And(a, b) => {
        let%bind a = evalToBool(a);
        let%bind b = evalToBool(b);
        return(V.Bool(a && b));
      }
    | [@implicit_arity] E.Or(a, b) => {
        let%bind a = evalToBool(a);
        let%bind b = evalToBool(b);
        return(V.Bool(a || b));
      }
    | E.Not(a) => {
        let%bind a = evalToBool(a);
        return(V.Bool(!a));
      }
    | [@implicit_arity] E.Rel(relop, a, b) => {
        let%bind a = eval(a);
        let%bind b = eval(b);
        let r =
          switch (relop) {
          | E.EQ => V.equal(a, b)
          | E.NEQ => !V.equal(a, b)
          };

        return(V.Bool(r));
      }
    | E.Concat(exprs) => {
        let f = (s, expr) => {
          let%bind v = evalToString(expr);
          return(s ++ v);
        };

        let%bind v = Result.List.foldLeft(~f, ~init="", exprs);
        return(V.String(v));
      };

  eval(expr);
};

let preserveEnvVar = name => Result.return(V.String("$" ++ name));

let render =
    (~envVar=?, ~pathSep="/", ~colon=":", ~scope: scope, string: string) => {
  open Result.Syntax;
  let envVar =
    switch (envVar) {
    | None => preserveEnvVar
    | Some(f) => f
    };

  switch%bind (eval(~envVar, ~pathSep, ~colon, ~scope, string)) {
  | V.String(v) => return(v)
  | V.Bool(true) => return("true")
  | V.Bool(false) => return("false")
  };
};

let%test_module "CommandExpr" =
  (module
   {
     let expectParseOk = (s, expr) =>
       switch (parse(s)) {
       | Ok(res) =>
         if (!E.equal(res, expr)) {
           Format.printf(" Parsing:@[<v 2>@\n%s@]@\n", s);
           Format.printf("Expected:@[<v 2>@\n%a@]@\n", E.pp, expr);
           Format.printf("     Got:@[<v 2>@\n%a@]@\n", E.pp, res);
           false;
         } else {
           true;
         }
       | Error(err) =>
         let msg = Printf.sprintf("parse error: %s", err);
         print_endline(msg);
         false;
       };

     let%test "parse just string" =
       expectParseOk("something", String("something"));

     let%test "parse just string w/ leading space" =
       expectParseOk(" something", String(" something"));

     let%test "parse just string w/ trailing space" =
       expectParseOk("something ", String("something "));

     let%test "string with squote" =
       expectParseOk("somet'ok'hing", String("somet'ok'hing"))
       && expectParseOk("somet'ok' hing", String("somet'ok' hing"))
       && expectParseOk("somet 'ok'hing", String("somet 'ok'hing"));

     let%test "string with dquote" =
       expectParseOk("somet\"ok\"hing", String("somet\"ok\"hing"))
       && expectParseOk("somet\"ok\" hing", String("somet\"ok\" hing"))
       && expectParseOk("somet \"ok\"hing", String("somet \"ok\"hing"));

     let%test "parse simple var" =
       expectParseOk("#{hi}", [@implicit_arity] Var(None, "hi"))
       && expectParseOk("#{hi }", [@implicit_arity] Var(None, "hi"))
       && expectParseOk("#{ hi}", [@implicit_arity] Var(None, "hi"));

     let%test "parse var+" =
       expectParseOk(
         "#{hi}#{world}",
         Concat([
           [@implicit_arity] Var(None, "hi"),
           [@implicit_arity] Var(None, "world"),
         ]),
       );

     let%test "parse string + var" =
       expectParseOk(
         "hello #{world}",
         Concat([String("hello "), [@implicit_arity] Var(None, "world")]),
       )
       && expectParseOk(
            " #{world}",
            Concat([String(" "), [@implicit_arity] Var(None, "world")]),
          )
       && expectParseOk(
            "#{world} ",
            Concat([[@implicit_arity] Var(None, "world"), String(" ")]),
          )
       && expectParseOk(
            "hello#{world}",
            Concat([String("hello"), [@implicit_arity] Var(None, "world")]),
          )
       && expectParseOk(
            "#{hello} world",
            Concat([
              [@implicit_arity] Var(None, "hello"),
              String(" world"),
            ]),
          )
       && expectParseOk(
            "#{hello}world",
            Concat([[@implicit_arity] Var(None, "hello"), String("world")]),
          );

     let%test "parse complex var" =
       expectParseOk(
         "#{hi world}",
         Concat([
           [@implicit_arity] Var(None, "hi"),
           [@implicit_arity] Var(None, "world"),
         ]),
       )
       && expectParseOk(
            "#{h-i world}",
            Concat([
              [@implicit_arity] Var(None, "h-i"),
              [@implicit_arity] Var(None, "world"),
            ]),
          )
       && expectParseOk(
            "#{hi :}",
            Concat([[@implicit_arity] Var(None, "hi"), Colon]),
          )
       && expectParseOk(
            "#{hi : world}",
            Concat([
              [@implicit_arity] Var(None, "hi"),
              Colon,
              [@implicit_arity] Var(None, "world"),
            ]),
          )
       && expectParseOk(
            "#{hi /}",
            Concat([[@implicit_arity] Var(None, "hi"), PathSep]),
          )
       && expectParseOk(
            "#{hi / world}",
            Concat([
              [@implicit_arity] Var(None, "hi"),
              PathSep,
              [@implicit_arity] Var(None, "world"),
            ]),
          );

     let%test "parse var with env vars" =
       expectParseOk(
         "#{hi / $world}",
         Concat([
           [@implicit_arity] Var(None, "hi"),
           PathSep,
           EnvVar("world"),
         ]),
       );

     let%test "parse var with literals" =
       expectParseOk("#{'world'}", String("world"))
       && expectParseOk("#{/ 'world'}", Concat([PathSep, String("world")]))
       && expectParseOk("#{: 'world'}", Concat([Colon, String("world")]))
       && expectParseOk("#{/'world'}", Concat([PathSep, String("world")]))
       && expectParseOk("#{:'world'}", Concat([Colon, String("world")]))
       && expectParseOk("#{'world' /}", Concat([String("world"), PathSep]))
       && expectParseOk("#{'world' :}", Concat([String("world"), Colon]))
       && expectParseOk("#{'world'/}", Concat([String("world"), PathSep]))
       && expectParseOk("#{'world':}", Concat([String("world"), Colon]))
       && expectParseOk(
            "#{hi'world'}",
            Concat([[@implicit_arity] Var(None, "hi"), String("world")]),
          )
       && expectParseOk(
            "#{'world'hi}",
            Concat([String("world"), [@implicit_arity] Var(None, "hi")]),
          )
       && expectParseOk(
            "#{hi / 'world'}",
            Concat([
              [@implicit_arity] Var(None, "hi"),
              PathSep,
              String("world"),
            ]),
          )
       && expectParseOk(
            "#{'hi''world'}",
            Concat([String("hi"), String("world")]),
          )
       && expectParseOk("#{'h\\'i'}", String("h'i"));

     let%test "parse namespace" =
       expectParseOk("#{ns.hi}", [@implicit_arity] Var(Some("ns"), "hi"))
       && expectParseOk(
            "#{n-s.hi}",
            [@implicit_arity] Var(Some("n-s"), "hi"),
          )
       && expectParseOk(
            "#{@scope/pkg.hi}",
            [@implicit_arity] Var(Some("@scope/pkg"), "hi"),
          )
       && expectParseOk(
            "#{@s-cope/pkg.hi}",
            [@implicit_arity] Var(Some("@s-cope/pkg"), "hi"),
          )
       && expectParseOk(
            "#{@scope/pkg.hi 'hey'}",
            Concat([
              [@implicit_arity] Var(Some("@scope/pkg"), "hi"),
              String("hey"),
            ]),
          );

     let%test "parse conditionals (strings in then / else)" =
       expectParseOk(
         "#{lwt.installed ? '--enable-lwt' : '--disable-lwt'}",
         [@implicit_arity]
         Condition(
           [@implicit_arity] Var(Some("lwt"), "installed"),
           String("--enable-lwt"),
           String("--disable-lwt"),
         ),
       );

     let%test "parse conditionals (vars in then / else)" =
       expectParseOk(
         "#{lwt.installed ? then : else}",
         [@implicit_arity]
         Condition(
           [@implicit_arity] Var(Some("lwt"), "installed"),
           [@implicit_arity] Var(None, "then"),
           [@implicit_arity] Var(None, "else"),
         ),
       );

     let%test "parse conditionals (lists in then / else)" =
       expectParseOk(
         "#{lwt.installed ? (then : then) : (else : else)}",
         [@implicit_arity]
         Condition(
           [@implicit_arity] Var(Some("lwt"), "installed"),
           Concat([
             [@implicit_arity] Var(None, "then"),
             Colon,
             [@implicit_arity] Var(None, "then"),
           ]),
           Concat([
             [@implicit_arity] Var(None, "else"),
             Colon,
             [@implicit_arity] Var(None, "else"),
           ]),
         ),
       );

     let%test "parse conj" =
       expectParseOk(
         "#{lwt.installed && async.installed}",
         [@implicit_arity]
         And(
           [@implicit_arity] Var(Some("lwt"), "installed"),
           [@implicit_arity] Var(Some("async"), "installed"),
         ),
       );

     let%test "parse disj" =
       expectParseOk(
         "#{lwt.installed || async.installed}",
         [@implicit_arity]
         Or(
           [@implicit_arity] Var(Some("lwt"), "installed"),
           [@implicit_arity] Var(Some("async"), "installed"),
         ),
       );

     let%test "parse eq" =
       expectParseOk(
         "#{lwt.installed == async.installed}",
         [@implicit_arity]
         Rel(
           EQ,
           [@implicit_arity] Var(Some("lwt"), "installed"),
           [@implicit_arity] Var(Some("async"), "installed"),
         ),
       );

     let%test "parse neq" =
       expectParseOk(
         "#{lwt.installed != async.installed}",
         [@implicit_arity]
         Rel(
           NEQ,
           [@implicit_arity] Var(Some("lwt"), "installed"),
           [@implicit_arity] Var(Some("async"), "installed"),
         ),
       );

     let%test "parse precedence disj / conj" =
       expectParseOk(
         "#{lwt || async && mirage}",
         [@implicit_arity]
         Or(
           [@implicit_arity] Var(None, "lwt"),
           [@implicit_arity]
           And(
             [@implicit_arity] Var(None, "async"),
             [@implicit_arity] Var(None, "mirage"),
           ),
         ),
       )
       && expectParseOk(
            "#{mirage && lwt || async}",
            [@implicit_arity]
            Or(
              [@implicit_arity]
              And(
                [@implicit_arity] Var(None, "mirage"),
                [@implicit_arity] Var(None, "lwt"),
              ),
              [@implicit_arity] Var(None, "async"),
            ),
          )
       && expectParseOk(
            "#{(lwt || async) && mirage}",
            [@implicit_arity]
            And(
              [@implicit_arity]
              Or(
                [@implicit_arity] Var(None, "lwt"),
                [@implicit_arity] Var(None, "async"),
              ),
              [@implicit_arity] Var(None, "mirage"),
            ),
          )
       && expectParseOk(
            "#{mirage && (lwt || async)}",
            [@implicit_arity]
            And(
              [@implicit_arity] Var(None, "mirage"),
              [@implicit_arity]
              Or(
                [@implicit_arity] Var(None, "lwt"),
                [@implicit_arity] Var(None, "async"),
              ),
            ),
          );

     let%test "parse precedence conj / eq" =
       expectParseOk(
         "#{lwt == async && mirage}",
         [@implicit_arity]
         And(
           [@implicit_arity]
           Rel(
             EQ,
             [@implicit_arity] Var(None, "lwt"),
             [@implicit_arity] Var(None, "async"),
           ),
           [@implicit_arity] Var(None, "mirage"),
         ),
       )
       && expectParseOk(
            "#{lwt != async && mirage}",
            [@implicit_arity]
            And(
              [@implicit_arity]
              Rel(
                NEQ,
                [@implicit_arity] Var(None, "lwt"),
                [@implicit_arity] Var(None, "async"),
              ),
              [@implicit_arity] Var(None, "mirage"),
            ),
          )
       && expectParseOk(
            "#{mirage && lwt == async}",
            [@implicit_arity]
            And(
              [@implicit_arity] Var(None, "mirage"),
              [@implicit_arity]
              Rel(
                EQ,
                [@implicit_arity] Var(None, "lwt"),
                [@implicit_arity] Var(None, "async"),
              ),
            ),
          )
       && expectParseOk(
            "#{mirage && lwt != async}",
            [@implicit_arity]
            And(
              [@implicit_arity] Var(None, "mirage"),
              [@implicit_arity]
              Rel(
                NEQ,
                [@implicit_arity] Var(None, "lwt"),
                [@implicit_arity] Var(None, "async"),
              ),
            ),
          )
       && expectParseOk(
            "#{(mirage && lwt) != async}",
            [@implicit_arity]
            Rel(
              NEQ,
              [@implicit_arity]
              And(
                [@implicit_arity] Var(None, "mirage"),
                [@implicit_arity] Var(None, "lwt"),
              ),
              [@implicit_arity] Var(None, "async"),
            ),
          );

     let%test "parse precedence not" =
       expectParseOk(
         "#{!lwt == async}",
         [@implicit_arity]
         Rel(
           EQ,
           Not([@implicit_arity] Var(None, "lwt")),
           [@implicit_arity] Var(None, "async"),
         ),
       )
       && expectParseOk(
            "#{lwt == !async}",
            [@implicit_arity]
            Rel(
              EQ,
              [@implicit_arity] Var(None, "lwt"),
              Not([@implicit_arity] Var(None, "async")),
            ),
          )
       && expectParseOk(
            "#{!lwt != async}",
            [@implicit_arity]
            Rel(
              NEQ,
              Not([@implicit_arity] Var(None, "lwt")),
              [@implicit_arity] Var(None, "async"),
            ),
          )
       && expectParseOk(
            "#{lwt != !async}",
            [@implicit_arity]
            Rel(
              NEQ,
              [@implicit_arity] Var(None, "lwt"),
              Not([@implicit_arity] Var(None, "async")),
            ),
          );

     let expectRenderOk = (scope, s, expected) =>
       switch (render(~scope, s)) {
       | Ok(v) =>
         if (v != expected) {
           Format.printf("  Render:@[<v 2>@\n%s@]@\n", s);
           Format.printf("Expected:@[<v 2>@\n%s@]@\n", expected);
           Format.printf("     Got:@[<v 2>@\n%s@]@\n", v);
           false;
         } else {
           true;
         }
       | Error(err) =>
         let msg = Printf.sprintf("error: %s", err);
         print_endline(msg);
         false;
       };

     let expectRenderError = (scope, s, expectedError) =>
       switch (render(~scope, s)) {
       | Ok(_) => false
       | Error(err) =>
         let err = String.trim(err);
         if (String.trim(expectedError) != err) {
           Printf.printf("Expected: %s\n", expectedError);
           Printf.printf("     Got: %s\n", err);
           false;
         } else {
           true;
         };
       };

     let scope =
       fun
       | (None, "name") => Some(V.String("pkg"))
       | (None, "isTrue") => Some(V.Bool(true))
       | (None, "isFalse") => Some(V.Bool(false))
       | (None, "opam:os") => Some(V.String("MSDOS"))
       | (None, "os") => Some(V.String("OS/2"))
       | (Some("self"), "lib") => Some(V.String("store/lib"))
       | (Some("@opam/pkg"), "lib") => Some(V.String("store/opam-pkg/lib"))
       | (Some("@opam/pkg1"), "installed") => Some(V.Bool(true))
       | (Some("@opam/pkg2"), "installed") => Some(V.Bool(true))
       | (Some("@opam/pkg-not"), "installed") => Some(V.Bool(false))
       | _ => None;

     let%test "render" =
       expectRenderOk(scope, "Hello, #{name}!", "Hello, pkg!")
       && expectRenderOk(scope, "#{self.lib / $NAME}", "store/lib/$NAME")
       && expectRenderOk(scope, "#{isTrue ? 'ok' : 'oops'}", "ok")
       && expectRenderOk(scope, "#{isFalse ? 'oops' : 'ok'}", "ok")
       && expectRenderOk(scope, "#{!isFalse ? 'ok' : 'oops'}", "ok")
       && expectRenderOk(scope, "#{isFalse && isTrue ? 'oops' : 'ok'}", "ok")
       && expectRenderOk(scope, "#{isFalse || isTrue ? 'ok' : 'oops'}", "ok")
       && expectRenderOk(scope, "#{os == 'OS/2' ? 'ok' : 'oops'}", "ok")
       && expectRenderOk(scope, "#{os != 'macOs' ? 'ok' : 'oops'}", "ok");

     let%test "render opam" =
       expectRenderOk(scope, "Hello, %{os}%!", "Hello, MSDOS!")
       && expectRenderOk(scope, "%{pkg:lib}%", "store/opam-pkg/lib")
       && expectRenderOk(scope, "%{pkg1:enable}%", "enable")
       && expectRenderOk(scope, "%{pkg-not:enable}%", "disable")
       && expectRenderOk(scope, "%{pkg1+pkg2:enable}%", "enable")
       && expectRenderOk(scope, "%{pkg1+pkg-not:enable}%", "disable")
       && expectRenderOk(scope, "%{pkg1:installed}%", "true")
       && expectRenderOk(scope, "%{pkg-not:installed}%", "false")
       && expectRenderOk(scope, "%{pkg1+pkg2:installed}%", "true")
       && expectRenderOk(scope, "%{pkg1+pkg-not:installed}%", "false");

     let%test "render errors" =
       expectRenderError(
         scope,
         "#{unknown}",
         "Error: Undefined variable 'unknown'",
       )
       && expectRenderError(
            scope,
            "#{ns.unknown}",
            "Error: Undefined variable 'ns.unknown'",
          )
       && expectRenderError(
            scope,
            "#{ns.unknown",
            "Error: unexpected end of string:\n  >\n  > #{ns.unknown...\n  >            ^",
          )
       && expectRenderError(
            scope,
            "#{'some",
            "Error: unexpected end of string:\n  >\n  > #{'some...\n  >       ^",
          )
       && expectRenderError(
            scope,
            "#{'some}",
            "Error: unexpected end of string:\n  >\n  > #{'some}...\n  >        ^",
          )
       && expectRenderError(
            scope,
            "#{cond ^}",
            "Error: unexpected token '^' found:\n  >\n  > #{cond ^}...\n  >        ^",
          );

     let%test "syntax errors" =
       expectRenderError(scope, "#{cond &&}", "Error: Syntax error")
       && expectRenderError(scope, "#{cond ?}", "Error: Syntax error")
       && expectRenderError(scope, "#{cond ? then}", "Error: Syntax error")
       && expectRenderError(scope, "#{cond ? then :}", "Error: Syntax error");
   });
