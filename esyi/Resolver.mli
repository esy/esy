(** Package request resolver *)
type t

(** Make new resolver *)
val make : cfg:Config.t -> unit -> t RunAsync.t

(** Resolve package request into a list of packages *)
val resolve : req:PackageInfo.Req.t -> t -> Package.t list RunAsync.t
