module type MEMOIZEABLE = sig
  type key
  type value
end

module type MEMOIZE = sig
  type t

  type key
  type value

  val make : ?size:int -> unit -> t
  val compute : t -> key -> (key -> value) -> value
  val ensureComputed : t -> key -> (key -> value) -> unit
  val put : t -> key -> value -> unit
  val get : t -> key -> value option
  val values : t -> (key * value) list
end

module type MAKE_MEMOIZE = functor (C: MEMOIZEABLE) -> sig
  include MEMOIZE with
    type key := C.key
    and type value := C.value
end

module Make : MAKE_MEMOIZE = functor (C : MEMOIZEABLE) -> struct
  type key = C.key
  type value = C.value
  type t = (key, value) Hashtbl.t

  let make ?(size=200) () =
    let cache = Hashtbl.create size in
    cache

  let put cache k v =
    Hashtbl.replace cache k v

  let get = Hashtbl.find_opt

  let values cache =
    let f k v values =
      (k, v)::values
    in Hashtbl.fold f cache []

  let compute cache k compute =
    try Hashtbl.find cache k with
    | Not_found ->
      let v = compute k in
      Hashtbl.add cache k v;
      v

  let ensureComputed cache k compute =
    if not (Hashtbl.mem cache k)
    then Hashtbl.add cache k (compute k)

end

type ('key, 'value) t = ('key, 'value) Hashtbl.t

let make ?(size=200) () =
  let cache = Hashtbl.create size in
  cache

let put cache k v =
  Hashtbl.replace cache k v

let get = Hashtbl.find_opt

let values cache =
  let f k v values =
    (k, v)::values
  in Hashtbl.fold f cache []

let compute cache k compute =
  try Hashtbl.find cache k with
  | Not_found ->
    let v = compute k in
    Hashtbl.add cache k v;
    v

let ensureComputed cache k compute =
  if not (Hashtbl.mem cache k)
  then Hashtbl.add cache k (compute k)
