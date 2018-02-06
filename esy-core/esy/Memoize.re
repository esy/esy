type cached('key, 'result) = ('key, unit => 'result) => 'result;

let create = (~size=200) : cached('key, 'result) => {
  let cache = Hashtbl.create(size);
  let lookup = (key, compute) =>
    try (Hashtbl.find(cache, key)) {
    | Not_found =>
      let promise = compute();
      Hashtbl.add(cache, key, promise);
      promise;
    };
  lookup;
};