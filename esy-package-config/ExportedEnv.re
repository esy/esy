[@ocaml.warning "-32"];
[@deriving (show, ord)]
type scope =
  | Local
  | Global;

let scope_of_yojson =
  fun
  | `String("global") => Ok(Global)
  | `String("local") => Ok(Local)
  | _ => Error("expected either \"local\" or \"global\"");

let scope_to_yojson =
  fun
  | Local => `String("local")
  | Global => `String("global");

module Item = {
  [@deriving yojson]
  type t = {
    [@key "val"]
    value: option(string),
    scope: [@default Local] scope_,
    exclusive: [@default false] bool,
  }
  /* this is just to prevent refmt to misbehave */
  and scope_ = scope;
};

[@deriving (show, ord)]
type value =
  | Set(string)
  | Unset;
[@ocaml.warning "-32"];
[@deriving (show, ord)]
type item = {
  name: string,
  value,
  scope,
  exclusive: bool,
};

[@deriving ord]
type t = StringMap.t(item);

let empty = StringMap.empty;
let set = (~exclusive=?, scope, name, value) => {
  name,
  value: Set(value),
  scope,
  exclusive: Option.orDefault(~default=false, exclusive),
};
let unset = (~exclusive=?, scope, name) => {
  name,
  value: Unset,
  scope,
  exclusive: Option.orDefault(~default=false, exclusive),
};

let item_of_yojson = (name, json) => {
  open Result.Syntax;
  let* {Item.value, scope, exclusive} = Item.of_yojson(json);
  let value =
    switch (value) {
    | Some(value) => Set(value)
    | None => Unset
    };
  return({name, value, scope, exclusive});
};

let of_yojson =
  fun
  | `Assoc(items) => {
      open Result.Syntax;
      let f = (items, (name, json)) => {
        let* item = item_of_yojson(name, json);
        return(StringMap.add(name, item, items));
      };

      Result.List.foldLeft(~f, ~init=StringMap.empty, items);
    }
  | _ => Error("expected an object");

let item_to_yojson = item =>
  `Assoc([
    (
      "val",
      switch (item.value) {
      | Set(value) => `String(value)
      | Unset => `Null
      },
    ),
    ("scope", scope_to_yojson(item.scope)),
    ("exclusive", `Bool(item.exclusive)),
  ]);

let to_yojson = env => {
  let items = {
    let f = ((name, item)) => (name, item_to_yojson(item));
    List.map(~f, StringMap.bindings(env));
  };

  `Assoc(items);
};

let pp = {
  let ppItem = (fmt, (name, item)) =>
    Fmt.pf(fmt, "%s: %a", name, pp_item, item);

  StringMap.pp(~sep=Fmt.any(", "), ppItem);
};

let show = env => Format.asprintf("%a", pp, env);

module Override = {
  [@deriving (ord, show)]
  type t = StringMap.Override.t(item);

  let of_yojson = StringMap.Override.of_yojson(item_of_yojson);
  let to_yojson = StringMap.Override.to_yojson(item_to_yojson);
};
