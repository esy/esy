(* module Installation = EsyInstall.Installation *)
(* module Id = EsyInstall.Solution.Id *)

(* type build = { *)
(*   package : Installation.Package.t; *)
(*   build : Manifest.Build.t; *)
(* } [@@deriving yojson] *)

(* include Graph.Make(struct *)
(*   type t = build *)
(*   let compare a b = Id.compare a.package.id b.package.id *)
(* end) *)

(* type t = { *)
(*   root : Id.t; *)
(*   builds : build Id.Map.t; *)
(* } *)

(* let ofInstallation (installation : Installation.t) = *)
(*   installation *)
