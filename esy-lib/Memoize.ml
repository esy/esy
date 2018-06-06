type ('k, 'v) t = ('k, 'v) Hashtbl.t

let make ?(size=200) () =
  let cache = Hashtbl.create size in
  cache

let compute cache k compute =
  try Hashtbl.find cache k with
  | Not_found ->
    let v = compute k in
    Hashtbl.add cache k v;
    v
