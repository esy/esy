[@deriving ord]
type t = {
  name: string,
  version: Version.t,
  digest: option(string),
};

let make = (name, version, digest) => {
  let digest =
    switch (digest) {
    | Some(digest) =>
      let digest = Digestv.toHex(digest);
      let digest = String.sub(digest, 0, 8);
      Some(digest);
    | None => None
    };

  {name, version, digest};
};
let name = ({name, _}) => name;
let version = ({version, _}) => version;

let findatinv = Str.regexp("__AT__");
let findat = Str.regexp("@");

let showVersion = v => {
  let v = Version.show(v);
  let v = Str.global_replace(findat, "__AT__", v);
  v;
};

let parseVersion = s => {
  let s = Str.global_replace(findatinv, "@", s);
  Version.parse(s);
};

let parse = v => {
  open Result.Syntax;
  let split = v => Astring.String.cut(~sep="@", v);
  let rec parseName = v =>
    Result.Syntax.(
      switch (split(v)) {
      | Some(("", name)) =>
        let* (name, version) = parseName(name);
        return(("@" ++ name, version));
      | Some((name, version)) => return((name, version))
      | None => error("invalid id: missing version")
      }
    );

  let* (name, v) = parseName(v);
  switch (split(v)) {
  | Some((version, digest)) =>
    let* version = parseVersion(version);
    return({name, version, digest: Some(digest)});
  | None =>
    let* version = parseVersion(v);
    return({name, version, digest: None});
  };
};

let show = ({name, version, digest}) => {
  let version = showVersion(version);
  switch (digest) {
  | Some(digest) => name ++ "@" ++ version ++ "@" ++ digest
  | None => name ++ "@" ++ version
  };
};

let pp = (fmt, id) => Fmt.pf(fmt, "%s", show(id));

let ppNoHash = (fmt, id) =>
  Fmt.pf(fmt, "%s", id.name ++ "@" ++ Version.show(id.version));

let to_yojson = id => `String(show(id));

let of_yojson =
  fun
  | `String(v) => parse(v)
  | _ => Error("expected string");

module Set = {
  include Set.Make({
    type nonrec t = t;
    let compare = compare;
  });

  let to_yojson = set => {
    let f = (el, elems) => [to_yojson(el), ...elems];
    `List(fold(f, set, []));
  };

  let of_yojson = json => {
    let elems =
      switch (json) {
      | `List(elems) => Result.List.map(~f=of_yojson, elems)
      | _ => Error("expected array")
      };

    Result.map(~f=of_list, elems);
  };
};

module Map = {
  include Map.Make({
    type nonrec t = t;
    let compare = compare;
  });

  let pp = (ppValue, fmt, map) => {
    let ppBinding = (fmt, (k, v)) =>
      Fmt.pf(fmt, "%a = %a", pp, k, ppValue, v);
    Fmt.pf(
      fmt,
      "PackageId.Map { %a }",
      Fmt.(list(ppBinding)),
      bindings(map),
    );
  };

  let to_yojson = (v_to_yojson, map) => {
    let items = {
      let f = (id, v, items) => {
        let k = show(id);
        [(k, v_to_yojson(v)), ...items];
      };

      fold(f, map, []);
    };

    `Assoc(items);
  };

  let of_yojson = v_of_yojson =>
    Result.Syntax.(
      fun
      | `Assoc(items) => {
          let f = (map, (k, v)) => {
            let* k = parse(k);
            let* v = v_of_yojson(v);
            return(add(k, v, map));
          };

          Result.List.foldLeft(~f, ~init=empty, items);
        }
      | _ => error("expected an object")
    );
};
