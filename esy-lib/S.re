module type PRINTABLE = {
  type t;

  let pp: Fmt.t(t);
  let show: t => string;
};

module type JSONABLE = {
  type t;

  let to_yojson: t => Yojson.Safe.json;
  let of_yojson: Yojson.Safe.json => result(t, string);
};

module type COMPARABLE = {
  type t;

  let compare: (t, t) => int;
};

module type COMMON = {
  type t;

  include COMPARABLE with type t := t;
  include PRINTABLE with type t := t;
  include JSONABLE with type t := t;
};
