type t = Override.t list

val empty : t
val isEmpty : t -> bool

val add : Override.t -> t -> t
(* [add override overrides] adds single [override] on top of [overrides]. *)

val addMany : Override.t list -> t -> t
(* [add override_list overrides] adds many [overridea_list] overrides on top of [overrides]. *)

val merge : t -> t -> t
(* [merge newOverrides overrides] adds [newOverrides] on top of [overrides]. *)

val foldWithBuildOverrides :
  f:('v -> Override.build -> 'v)
  -> init:'v
  -> t
  -> 'v RunAsync.t

val foldWithInstallOverrides :
  f:('v -> Override.install -> 'v)
  -> init:'v
  -> t
  -> 'v RunAsync.t
