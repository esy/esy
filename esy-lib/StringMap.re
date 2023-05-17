include Astring.String.Map;

let mergeOverride = (a, b) => {
  let f = (_k, a, b) =>
    switch (a, b) {
    | (Some(a), None) => Some(a)
    | (Some(_), Some(b))
    | (None, Some(b)) => Some(b)
    | (None, None) => None
    };

  merge(f, a, b);
};

let values = map => {
  let f = (_k, v, vs) => [v, ...vs];
  fold(f, map, []);
};

let keys = map => {
  let f = (k, _v, ks) => [k, ...ks];
  fold(f, map, []);
};

let to_yojson = (v_to_yojson, map) => {
  let items = {
    let f = (k, v, items) => [(k, v_to_yojson(v)), ...items];
    fold(f, map, []);
  };

  `Assoc(items);
};

let of_yojson = v_of_yojson =>
  Result.Syntax.(
    fun
    | `Assoc(items) => {
        let f = (items, (k, json)) => {
          let* v = v_of_yojson(json);
          return(add(k, v, items));
        };

        Result.List.foldLeft(~f, ~init=empty, items);
      }
    | _ => Error("expected an object")
  );

type stringMap('a) = t('a);
let compare_stringMap = compare;

module Override: {
  type t('a) = stringMap(override('a))
  and override('a) =
    | Drop
    | Edit('a);

  let apply: (stringMap('a), t('a)) => stringMap('a);

  let compare: (('a, 'a) => int, t('a), t('a)) => int;

  let of_yojson:
    ((string, Yojson.Safe.t) => result('a, string), Yojson.Safe.t) =>
    result(t('a), string);

  let to_yojson: ('a => Yojson.Safe.t, t('a)) => Yojson.Safe.t;

  let pp: Fmt.t('a) => Fmt.t(t('a));
} = {
  [@deriving ord]
  type t('a) = stringMap(override('a))
  and override('a) =
    | Drop
    | Edit('a);

  let apply = (map, override) => {
    let map = {
      let f = (name, override, map) =>
        switch (override) {
        | Drop => remove(name, map)
        | Edit(value) => add(name, value, map)
        };

      fold(f, override, map);
    };

    map;
  };

  let of_yojson = value_of_yojson =>
    fun
    | `Assoc(items) => {
        open Result.Syntax;
        let f = (map, (name, json)) =>
          switch (json) {
          | `Null =>
            let override = Drop;
            return(add(name, override, map));
          | _ =>
            let* value = value_of_yojson(name, json);
            let override = Edit(value);
            return(add(name, override, map));
          };

        Result.List.foldLeft(~f, ~init=empty, items);
      }
    | _ => Error("expected an object");

  let to_yojson = (value_to_yojson, env) => {
    let items = {
      let f = ((name, override)) =>
        switch (override) {
        | Edit(value) => (name, value_to_yojson(value))
        | Drop => (name, `Null)
        };

      List.map(~f, bindings(env));
    };

    `Assoc(items);
  };

  let pp = pp_value => {
    let ppOverride = (fmt, override) =>
      switch (override) {
      | Drop => Fmt.any("remove", fmt, ())
      | Edit(v) => pp_value(fmt, v)
      };

    let ppItem = Fmt.(pair(~sep=any(": "), string, ppOverride));
    Fmt.braces(pp(~sep=Fmt.any(", "), ppItem));
  };

  let%test "apply: add key" = {
    let orig = empty |> add("a", "b");
    let override = empty |> add("c", Edit("d"));
    let result = apply(orig, override);
    let expect = empty |> add("a", "b") |> add("c", "d");
    compare_stringMap(String.compare, result, expect) == 0;
  };

  let%test "apply: drop key" = {
    let orig = empty |> add("a", "b") |> add("c", "d");
    let override = empty |> add("c", Drop);
    let result = apply(orig, override);
    let expect = empty |> add("a", "b");
    compare_stringMap(String.compare, result, expect) == 0;
  };

  let%test "apply: replace key" = {
    let orig = empty |> add("a", "b") |> add("c", "d");
    let override = empty |> add("c", Edit("d!"));
    let result = apply(orig, override);
    let expect = empty |> add("a", "b") |> add("c", "d!");
    compare_stringMap(String.compare, result, expect) == 0;
  };
};
