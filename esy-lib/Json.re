type t = Yojson.Safe.t;

type encoder('a) = 'a => t;
type decoder('a) = t => result('a, string);

let to_yojson = x => x;
let of_yojson = x => Ok(x);

let show = Yojson.Safe.pretty_to_string;
let pp = Yojson.Safe.pretty_print;

let compare = (a, b) =>
  String.compare(Yojson.Safe.to_string(a), Yojson.Safe.to_string(b));

let parse = data =>
  try(Run.return(Yojson.Safe.from_string(data))) {
  | Yojson.Json_error(msg) => Run.errorf("error parsing JSON: %s", msg)
  };

let parseJsonWith = (parser, json) => Run.ofStringError(parser(json));

let parseStringWith = (parser, data) =>
  try({
    let json = Yojson.Safe.from_string(data);
    parseJsonWith(parser, json);
  }) {
  | Yojson.Json_error(msg) => Run.errorf("error parsing JSON: %s", msg)
  };

let mergeAssoc = (items, update) => {
  let toMap = items => {
    let f = (map, (name, json)) => StringMap.add(name, json, map);
    List.fold_left(~f, ~init=StringMap.empty, items);
  };

  let items = toMap(items);
  let update = toMap(update);
  let result = StringMap.mergeOverride(items, update);
  StringMap.bindings(result);
};

module Decode = {
  let string = (json: t) =>
    switch (json) {
    | `String(v) => Ok(v)
    | _ => Error("expected string")
    };

  let nullable = (decode, json: t) =>
    switch (json) {
    | `Null => Ok(None)
    | json =>
      switch (decode(json)) {
      | Ok(v) => Ok(Some(v))
      | Error(err) => Error(err)
      }
    };

  let assoc = (json: t) =>
    switch (json) {
    | `Assoc(v) => Ok(v)
    | _ => Error("expected object")
    };

  let field = (~name, json: t) =>
    switch (json) {
    | `Assoc(items) =>
      switch (List.find_opt(~f=((k, _v)) => k == name, items)) {
      | Some((_, v)) => Ok(v)
      | None => Error("no such field: " ++ name)
      }
    | _ => Error("expected object")
    };

  let fieldOpt = (~name, json: t) =>
    switch (json) {
    | `Assoc(items) =>
      switch (List.find_opt(~f=((k, _v)) => k == name, items)) {
      | Some((_, v)) => Ok(Some(v))
      | None => Ok(None)
      }
    | _ => Error("expected object")
    };

  let fieldWith = (~name, parse, json) =>
    switch (field(~name, json)) {
    | Ok(v) => parse(v)
    | Error(err) => Error(err)
    };

  let fieldOptWith = (~name, parse, json) =>
    switch (fieldOpt(~name, json)) {
    | Ok(Some(v)) =>
      switch (parse(v)) {
      | Ok(v) => Ok(Some(v))
      | Error(err) => Error(err)
      }
    | Ok(None) => Ok(None)
    | Error(err) => Error(err)
    };

  let list = (~errorMsg="expected an array", value, json: t) =>
    switch (json) {
    | `List(items: list(t)) =>
      let f = (acc, v) =>
        switch (acc, value(v)) {
        | (Ok(acc), Ok(v)) => Ok([v, ...acc])
        | (Ok(_), Error(err)) => Error(err)
        | (err, _) => err
        };
      switch (List.fold_left(~f, ~init=Ok([]), items)) {
      | Ok(items) => Ok(List.rev(items))
      | error => error
      };
    | _ => Error(errorMsg)
    };

  let stringMap = (~errorMsg="expected an object", value, json: t) =>
    switch (json) {
    | `Assoc(items) =>
      let f = (acc, (k, v)) =>
        switch (acc, k, value(v)) {
        | (Ok(acc), k, Ok(v)) => Ok(StringMap.add(k, v, acc))
        | (Ok(_), _, Error(err)) => Error(err)
        | (err, _, _) => err
        };

      List.fold_left(~f, ~init=Ok(StringMap.empty), items);
    | _ => Error(errorMsg)
    };
};

module Encode = {
  type field = option((string, t));

  let opt = (encode, v) =>
    switch (v) {
    | None => `Null
    | Some(v) => encode(v)
    };

  let list = (encode, v) => `List(List.map(~f=encode, v));

  let string = v => `String(v);

  let assoc = fields => {
    let fields = List.filterNone(fields);
    `Assoc(fields);
  };

  let field = (name, encode, value) => Some((name, encode(value)));

  let fieldOpt = (name, encode, value) =>
    switch (value) {
    | None => None
    | Some(value) => Some((name, encode(value)))
    };
};

module Print: {
  let pp:
    (
      ~ppListBox: (~indent: int=?, Fmt.t(list(t))) => Fmt.t(list(t))=?,
      ~ppAssocBox: (~indent: int=?, Fmt.t(list((string, t)))) =>
                   Fmt.t(list((string, t)))
                     =?
    ) =>
    Fmt.t(t);

  let ppRegular: Fmt.t(t);
} = {
  let ppComma = Fmt.any(",@ ");

  /* from yojson */
  let hex = n =>
    Char.chr(
      if (n < 10) {
        n + 48;
      } else {
        n + 87;
      },
    );

  /* from yojson */
  let ppStringBody = (fmt, s) =>
    for (i in 0 to String.length(s) - 1) {
      switch (s.[i]) {
      | '"' => Format.pp_print_string(fmt, "\\\"")
      | '\\' => Format.pp_print_string(fmt, "\\\\")
      | '\b' => Format.pp_print_string(fmt, "\\b")
      | '\012' => Format.pp_print_string(fmt, "\\f")
      | '\n' => Format.pp_print_string(fmt, "\\n")
      | '\r' => Format.pp_print_string(fmt, "\\r")
      | '\t' => Format.pp_print_string(fmt, "\\t")
      | ('\000' .. '\031' | '\127') as c =>
        Format.pp_print_string(fmt, "\\u00");
        Format.pp_print_char(fmt, hex(Char.code(c) lsr 4));
        Format.pp_print_char(fmt, hex(Char.code(c) land 0xf));
      | c => Format.pp_print_char(fmt, c)
      };
    };

  let ppString = Fmt.quote(ppStringBody);

  let pp = (~ppListBox=Fmt.hvbox, ~ppAssocBox=Fmt.hvbox, fmt, json) => {
    let rec pp = (fmt, json) => Fmt.(vbox(ppSyn))(fmt, json)
    and ppSyn = (fmt, json) =>
      switch (json) {
      | `Bool(v) => Fmt.bool(fmt, v)
      | `Float(v) => Fmt.float(fmt, v)
      | `Int(v) => Fmt.int(fmt, v)
      | `Intlit(v) => Fmt.string(fmt, v)
      | `String(v) => ppString(fmt, v)
      | `Null => Fmt.any("null", fmt, ())
      | `Variant(tag, args) =>
        switch (args) {
        | None => ppSyn(fmt, `List([`String(tag)]))
        | Some(args) => ppSyn(fmt, `List([`String(tag), args]))
        }
      | `Tuple(items)
      | `List(items) =>
        let pp = (fmt, items) =>
          Format.fprintf(
            fmt,
            "[@;<0 0>%a@;<0 -2>]",
            Fmt.list(~sep=ppComma, ppListItem),
            items,
          );

        ppListBox(~indent=2, pp, fmt, items);
      | `Assoc(items) =>
        let pp = (fmt, items) =>
          Format.fprintf(
            fmt,
            "{@;<0 0>%a@;<0 -2>}",
            Fmt.list(~sep=ppComma, ppAssocItem),
            items,
          );

        ppAssocBox(~indent=2, pp, fmt, items);
      }
    and ppListItem = (fmt, item) => Format.fprintf(fmt, "%a", pp, item)
    and ppAssocItem = (fmt, (k, v)) =>
      switch (v) {
      | `List(items) =>
        Format.fprintf(
          fmt,
          "@[<hv 2>%a: [@,%a@;<0 -2>]@]",
          ppString,
          k,
          Fmt.list(~sep=ppComma, ppListItem),
          items,
        )
      | `Assoc(items) =>
        Format.fprintf(
          fmt,
          "@[<hv 2>%a: {@,%a@;<0 -2>}@]",
          ppString,
          k,
          Fmt.list(~sep=ppComma, ppAssocItem),
          items,
        )
      | _ => Format.fprintf(fmt, "@[<h 0>%a:@ %a@]", ppString, k, pp, v)
      };

    pp(fmt, json);
  };

  let ppRegular = pp(~ppListBox=Fmt.vbox, ~ppAssocBox=Fmt.vbox);
};
