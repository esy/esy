module Impl = {
  type t('key, 'value) = Hashtbl.t('key, Lazy.t('value));

  let make = (~size=200, ()) => {
    let cache = Hashtbl.create(size);
    cache;
  };

  let put = (cache, k, v) => {
    let v = Lazy.from_val(v);
    Hashtbl.add(cache, k, v);
  };

  let get = (cache, k) =>
    switch (Hashtbl.find_opt(cache, k)) {
    | Some(thunk) => Some(Lazy.force(thunk))
    | None => None
    };

  let values = cache => {
    let f = (k, thunk, values) => [(k, Lazy.force(thunk)), ...values];

    Hashtbl.fold(f, cache, []);
  };

  let compute = (cache, k, compute) => {
    let thunk =
      try(Hashtbl.find(cache, k)) {
      | Not_found =>
        let v = Lazy.from_fun(compute);
        Hashtbl.add(cache, k, v);
        v;
      };

    Lazy.force(thunk);
  };

  let ensureComputed = (cache, k, compute) =>
    if (!Hashtbl.mem(cache, k)) {
      let thunk = Lazy.from_fun(compute);
      Hashtbl.add(cache, k, thunk);
    };
};

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

module Make =
       (C: MEMOIZEABLE)
       : (MEMOIZE with type key := C.key and type value := C.value) => {
  type key = C.key;
  type value = C.value;

  type t = Impl.t(key, value);

  let make = Impl.make;
  let compute = Impl.compute;
  let ensureComputed = Impl.ensureComputed;
  let put = Impl.put;
  let get = Impl.get;
  let values = Impl.values;
};

include Impl;
