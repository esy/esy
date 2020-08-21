[@ocaml.warning "-32"];
[@deriving (show, ord)]
type item =
  | Unset({name: string})
  | Set({
      name: string,
      value: string,
    });

[@deriving ord]
type t = StringMap.t(item);

let empty = StringMap.empty;

let item_of_yojson = (name, json) =>
  switch (json) {
  | `String(value) => Ok(Set({name, value}))
  | `Null => Ok(Unset({name: name}))
  | _ => Error("expected string")
  };

let of_yojson =
  Result.Syntax.(
    fun
    | `Assoc(items) => {
        let f = (items, (name, json)) => {
          let%bind item = item_of_yojson(name, json);
          return(StringMap.add(name, item, items));
        };

        Result.List.foldLeft(~f, ~init=StringMap.empty, items);
      }
    | _ => Error("expected object")
  );

let item_to_yojson =
  fun
  | Set({value, _}) => `String(value)
  | Unset(_) => `Null;

let to_yojson = env => {
  let items = {
    let f = ((name, item)) => (name, item_to_yojson(item));
    List.map(~f, StringMap.bindings(env));
  };

  `Assoc(items);
};

let pp = {
  let ppItem = (fmt, (name, item)) =>
    switch (item) {
    | Set({value, _}) => Fmt.pf(fmt, "%s: %s", name, value)
    | Unset(_) => Fmt.pf(fmt, "unset %s", name)
    };

  StringMap.pp(~sep=Fmt.unit(", "), ppItem);
};

let show = env => Format.asprintf("%a", pp, env);

module Override = {
  [@deriving (ord, show)]
  type t = StringMap.Override.t(item);
  let of_yojson = StringMap.Override.of_yojson(item_of_yojson);
  let to_yojson = StringMap.Override.to_yojson(item_to_yojson);
};
