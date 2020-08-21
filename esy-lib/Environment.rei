/**

  Environment.

 */;

/** Environment binding */

module Binding: {
  type t('v);
  let origin: t('v) => option(string);
};

/** Environment representation over value type. */

module type S = {
  type ctx;
  type value;

  type t = StringMap.t(value);
  type env = t;

  let empty: t;
  let find: (string, t) => option(value);
  let add: (string, value, t) => t;
  let map: (~f: string => string, t) => t;

  let render: (ctx, t) => StringMap.t(string);

  include S.COMPARABLE with type t := t;
  include S.JSONABLE with type t := t;

  /** Environment as a list of bindings. */

  module Bindings: {
    type t = list(Binding.t(value));

    let pp: Fmt.t(t);

    let value: (~origin: string=?, string, value) => Binding.t(value);
    let prefixValue: (~origin: string=?, string, value) => Binding.t(value);
    let suffixValue: (~origin: string=?, string, value) => Binding.t(value);
    let remove: (~origin: string=?, string) => Binding.t(value);

    let empty: t;
    let render: (ctx, t) => list(Binding.t(string));
    let eval:
      (~platform: System.Platform.t=?, ~init: env=?, t) => result(env, string);
    let map: (~f: string => string, t) => t;

    let current: t;

    include S.COMPARABLE with type t := t;
  };
};

module Make:
  (V: Abstract.STRING) => S with type value = V.t and type ctx = V.ctx;

/** Environment which holds strings as values. */

include S with type value = string and type ctx = unit;

/** Render environment bindings as shell export statements. */

let renderToShellSource:
  (~header: string=?, ~platform: System.Platform.t=?, Bindings.t) =>
  Run.t(string);

let renderToList:
  (~platform: System.Platform.t=?, Bindings.t) => list((string, string));

let escapeDoubleQuote: string => string;
let escapeSingleQuote: string => string;
