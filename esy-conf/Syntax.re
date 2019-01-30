[@deriving show]
type t =
  | Value(value)
  | Abstraction(list(arg), t)
  | Application(t, list((string, t)))
  | Override(t, list((string, t)))
  | Binding(string, t, t) /* let NAME = X; E */
  | Projection(t, string)
  | Name(string)

and value =
  | Int(int)
  | String(string)
  | Bool(bool)
  | List(list(t))
  | Assoc(list((string, t)))

and arg = {
  name: string,
  typ: argtyp,
  default: option(t),
  desc: option(string),
}

and argtyp =
  | StringType
  | BoolType;

type scope = StringMap.t(Lazy.t(t));

/* TODO: make eval return result(syn, string) */
let rec eval = (scope: scope, syn: t) =>
  switch (syn) {
  | Value(_) => syn
  | Override(syn, ofields) =>
    switch (eval(scope, syn)) {
    | Value(Assoc(fields)) =>
      let f = ((k, syn)) => {
        let syn = eval(scope, syn);
        (k, syn);
      };
      let ofields = List.map(~f, ofields);
      let fields = fields @ ofields;
      Value(Assoc(fields));
    | _ => failwith("expected assoc")
    }
  | Abstraction(_) => syn
  | Application(f, args) =>
    let f = eval(scope, f);
    switch (f) {
    | Abstraction(_argspec, body) =>
      /* TODO: validate args against argspec */

      let f = (nextscope, (name, arg)) => {
        let arg = lazy (eval(scope, arg));
        StringMap.add(name, arg, nextscope);
      };
      let scope = List.fold_left(~init=scope, ~f, args);
      eval(scope, body);
    | _ => failwith("expected abstraction")
    };
  | Binding(name, expr, body) =>
    /* TODO: make bindings eval'ed in a lazy way */
    let expr = lazy (eval(scope, expr));
    let scope = StringMap.add(name, expr, scope);
    eval(scope, body);
  | Name(name) =>
    switch (StringMap.find_opt(name, scope)) {
    | None => failwith("not found: " ++ name)
    | Some(syn) => Lazy.force(syn)
    }
  | Projection(syn, name) =>
    switch (eval(scope, syn)) {
    | Value(Assoc(fields)) =>
      let f = ((k, _v)) => k == name;
      switch (List.find_opt(~f, fields)) {
      | None => failwith("not found key: " ++ name)
      | Some((_k, value)) => value
      };
    | _ => failwith("expected assoc")
    }
  };

let print_eval = syn => print_endline(show(eval(StringMap.empty, syn)));

let%expect_test "basic eval" = {
  print_eval(Value(Int(42)));
  %expect
  {| (Syntax.re.Value (Syntax.re.Int 42)) |};
};

let%expect_test "basic eval (binding)" = {
  /*
     let x = 42;
     x
   */
  print_eval(Binding("x", Value(Int(42)), Name("x")));
  %expect
  {| (Syntax.re.Value (Syntax.re.Int 42)) |};
};

let%expect_test "basic eval (function)" = {
  /*
     let make(y: int) = {value: y};
     make(y: 42).value
   */
  print_eval(
    Binding(
      "make",
      Abstraction([], Value(Assoc([("value", Name("y"))]))),
      Projection(
        Application(Name("make"), [("y", Value(Int(42)))]),
        "value",
      ),
    ),
  );
  %expect
  {|
    (Syntax.re.Value (Syntax.re.Int 42)) |};
};
