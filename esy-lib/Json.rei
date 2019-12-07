type t = Yojson.Safe.t;

type encoder('a) = 'a => t;
type decoder('a) = t => result('a, string);

let to_yojson: t => t;
let of_yojson: t => result(t, string);

let compare: (t, t) => int;

let show: (~std: bool=?, t) => string;
let pp: (~std: bool=?) => Fmt.t(t);

let parse: string => Run.t(t);
let parseJsonWith: (decoder('a), t) => Run.t('a);
let parseStringWith: (decoder('a), string) => Run.t('a);

let mergeAssoc:
  (list((string, t)), list((string, t))) => list((string, t));

module Decode: {
  let string: t => result(string, string);
  let assoc: t => result(list((string, t)), string);

  let nullable: decoder('a) => decoder(option('a));

  let field: (~name: string, t) => result(t, string);
  let fieldOpt: (~name: string, t) => result(option(t), string);

  let fieldWith: (~name: string, decoder('a)) => decoder('a);
  let fieldOptWith: (~name: string, decoder('a)) => decoder(option('a));

  let list: (~errorMsg: string=?, decoder('a)) => decoder(list('a));
  let stringMap:
    (~errorMsg: string=?, decoder('a)) => decoder(StringMap.t('a));
};

module Encode: {
  let opt: encoder('a) => encoder(option('a));
  let list: encoder('a) => encoder(list('a));
  let string: string => t;

  type field;

  let assoc: list(field) => t;
  let field: (string, encoder('a), 'a) => field;
  let fieldOpt: (string, encoder('a), option('a)) => field;
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
};
