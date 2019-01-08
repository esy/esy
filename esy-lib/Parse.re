include Angstrom;

module Let_syntax = {
  let map = (~f, p) => p >>| f;
  let bind = (~f, p) => p >>= f;
};

let ignore = p => p >>| (_ => ());

let const = (v, _) => return(v);

let maybe = p => option(None, p >>| (v => Some(v)));

let till = (c, p) => {
  let%bind input = take_while1(c);
  switch (parse_string(p, input)) {
  | Ok(fname) => return(fname)
  | Error(msg) => fail(msg)
  };
};

let pair = {
  let pair = (x, y) => (x, y);
  (a, b) => lift2(pair, a, b);
};

let hex =
  take_while1(
    fun
    | '0'..'9' => true
    | 'a'
    | 'b'
    | 'c'
    | 'd'
    | 'e'
    | 'f' => true
    | _ => false,
  )
  <?> "hex";

let parse = (p, input) =>
  switch (parse_string(p <* end_of_input, input)) {
  | Ok(v) => Ok(v)
  | Error(msg) =>
    let msg = Printf.sprintf({|parsing "%s": %s|}, input, msg);
    Error(msg);
  };

module Test = {
  let expectParses = (~pp, ~compare, parse, input, expectation) =>
    switch (parse(input)) {
    | Error(err) =>
      Format.printf("Error parsing '%s': %s@\n", input, err);
      false;
    | Ok(v) when compare(v, expectation) == 0 => true
    | Ok(v) =>
      Format.printf(
        "Error parsing '%s':@\n  expected: %a@\n  got:      %a@\n",
        input,
        pp,
        expectation,
        pp,
        v,
      );
      false;
    };

  let parse = (~sexp_of, parse, input) =>
    switch (parse(input)) {
    | Error(err) => Format.printf("ERROR: %s@.", err)
    | Ok(v) =>
      let sexp = sexp_of(v);
      Format.printf("%a@.", Sexplib0.Sexp.pp_hum, sexp);
    };
};
