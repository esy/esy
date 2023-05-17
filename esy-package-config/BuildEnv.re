[@ocaml.warning "-32"];
[@deriving (show, ord)]
type value =
  | Set(string)
  | Unset;
[@deriving (show, ord)]
type item = {
  name: string,
  value,
};

[@deriving ord]
type t = StringMap.t(item);

let empty = StringMap.empty;

let set = (name, value) => {name, value: Set(value)};
let unset = name => {name, value: Unset};

let item_of_yojson = (name, json) =>
  switch (json) {
  | `String(value) => Ok({name, value: Set(value)})
  | `Null => Ok({name, value: Unset})
  | _ => Error("expected string")
  };

let of_yojson =
  Result.Syntax.(
    fun
    | `Assoc(items) => {
        let f = (items, (name, json)) => {
          let* item = item_of_yojson(name, json);
          return(StringMap.add(name, item, items));
        };

        Result.List.foldLeft(~f, ~init=StringMap.empty, items);
      }
    | _ => Error("expected object")
  );

let item_to_yojson =
  fun
  | {value: Set(value), _} => `String(value)
  | {value: Unset, _} => `Null;

let to_yojson = env => {
  let items = {
    let f = ((name, item)) => (name, item_to_yojson(item));
    List.map(~f, StringMap.bindings(env));
  };

  `Assoc(items);
};

let pp = {
  let ppItem = (fmt, (name, {value, _})) =>
    switch (value) {
    | Set(value) => Fmt.pf(fmt, "%s: %s", name, value)
    | Unset => Fmt.pf(fmt, "unset %s", name)
    };

  StringMap.pp(~sep=Fmt.any(", "), ppItem);
};

let show = env => Format.asprintf("%a", pp, env);

module Override = {
  [@deriving (ord, show)]
  type t = StringMap.Override.t(item);
  let of_yojson = StringMap.Override.of_yojson(item_of_yojson);
  let to_yojson = StringMap.Override.to_yojson(item_to_yojson);
};
