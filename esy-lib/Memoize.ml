module Impl = struct
  type ('key, 'value) t = ('key, 'value Lazy.t) Hashtbl.t

  let make ?(size=200) () =
    let cache = Hashtbl.create size in
    cache

  let put cache k v =
    let v = Lazy.from_val v in
    Hashtbl.add cache k v

  let get cache k =
    match Hashtbl.find_opt cache k with
    | Some thunk -> Some (Lazy.force thunk)
    | None -> None

  let values cache =
    let f k thunk values =
      (k, Lazy.force thunk)::values
    in
    Hashtbl.fold f cache []

  let compute cache k compute =
    let thunk =
      try Hashtbl.find cache k with
      | Not_found ->
        let v = Lazy.from_fun compute in
        Hashtbl.add cache k v;
        v
    in
    Lazy.force thunk

  let ensureComputed cache k compute =
    if not (Hashtbl.mem cache k)
    then
      let thunk = Lazy.from_fun compute in
      Hashtbl.add cache k thunk
end

module type MEMOIZEABLE = sig
  type key
  type value
end

module type MEMOIZE = sig
  type t

  type key
  type value

  val make : ?size:int -> unit -> t
  val compute : t -> key -> (unit -> value) -> value
  val ensureComputed : t -> key -> (unit -> value) -> unit
  val put : t -> key -> value -> unit
  val get : t -> key -> value option
  val values : t -> (key * value) list
end

module Make (C : MEMOIZEABLE) :
  MEMOIZE
    with type key := C.key
    and type value := C.value = struct
  type key = C.key
  type value = C.value

  type t = (key, value) Impl.t

  let make = Impl.make
  let compute = Impl.compute
  let ensureComputed = Impl.ensureComputed
  let put = Impl.put
  let get = Impl.get
  let values = Impl.values
end

include Impl
