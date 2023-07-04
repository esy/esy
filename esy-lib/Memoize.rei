/** Parametrized API */;

type t('k, 'v);
let make: (~size: int=?, unit) => t('k, 'v);
let compute: (t('k, 'v), 'k, unit => 'v) => 'v;
let ensureComputed: (t('k, 'v), 'k, unit => 'v) => unit;
let put: (t('k, 'v), 'k, 'v) => unit;
let get: (t('k, 'v), 'k) => option('v);
let values: t('k, 'v) => list(('k, 'v));

/** Functorized API */;

module type MEMOIZEABLE = {
  type key;
  type value;
};

module type MEMOIZE = {
  type t;

  type key;
  type value;

  let make: (~size: int=?, unit) => t;
  let compute: (t, key, unit => value) => value;
  let ensureComputed: (t, key, unit => value) => unit;
  let put: (t, key, value) => unit;
  let get: (t, key) => option(value);
  let values: t => list((key, value));
};

module Make:
  (C: MEMOIZEABLE) =>
   {include MEMOIZE with type key := C.key and type value := C.value;};
