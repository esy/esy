(** Parametrized API *)

type ('k, 'v) t
val make : ?size:int -> unit -> ('k, 'v) t
val compute : ('k, 'v) t -> 'k -> ('k -> 'v) -> 'v
val ensureComputed : ('k, 'v) t -> 'k -> ('k -> 'v) -> unit
val put : ('k, 'v) t -> 'k -> 'v -> unit
val get : ('k, 'v) t -> 'k -> 'v option
val values : ('k, 'v) t -> ('k * 'v) list

(** Functorized API *)

module type MEMOIZEABLE = sig
  type key
  type value
end

module type MEMOIZE = functor (C: MEMOIZEABLE) -> sig
  type t

  type key = C.key
  type value = C.value

  val make : ?size:int -> unit -> t
  val compute : t -> key -> (key -> value) -> value
  val ensureComputed : t -> key -> (key -> value) -> unit
  val put : t -> key -> value -> unit
  val get : t -> key -> value option
  val values : t -> (key * value) list
end

module Make : MEMOIZE

