module BuildType = struct
  include BuildType
  include BuildType.AsInPackageJson
end

(* aliases for opam types with to_yojson implementations *)
module OpamTypes = struct
  type filter = OpamTypes.filter

  let filter_to_yojson filter = `String (OpamFilter.to_string filter)

  type command = arg list * filter option [@@deriving to_yojson]
  and arg = simple_arg * filter option
  and simple_arg = OpamTypes.simple_arg =
    | CString of string
    | CIdent of string
end

type commands =
  | OpamCommands of OpamTypes.command list
  | EsyCommands of CommandList.t
  | NoCommands
  [@@deriving to_yojson]

let pp_commands fmt cmds =
  match cmds with
  | OpamCommands cmds ->
    let json = `List (List.map ~f:OpamTypes.command_to_yojson cmds) in
    Fmt.pf fmt "OpamCommands %a" (Json.pp ~std:true) json
  | EsyCommands cmds ->
    let json = CommandList.to_yojson cmds in
    Fmt.pf fmt "EsyCommands %a" (Json.pp ~std:true) json
  | NoCommands ->
    Fmt.pf fmt "NoCommands"

type patch = Path.t * OpamTypes.filter option

let patch_to_yojson (path, filter) =
  let filter =
    match filter with
    | None -> `Null
    | Some filter -> `String (OpamFilter.to_string filter)
  in
  `Assoc ["path", Path.to_yojson path; "filter", filter]

let pp_patch fmt (path, _) = Fmt.pf fmt "Patch %a" Path.pp path

type t = {
  name : string option;
  version : Version.t option;
  buildType : BuildType.t;
  build : commands;
  buildDev : CommandList.t option;
  install : commands;
  patches : patch list;
  substs : Path.t list;
  exportedEnv : ExportedEnv.t;
  buildEnv : BuildEnv.t;
} [@@deriving to_yojson, show]

let empty ~name ~version () = {
  name;
  version;
  buildType = BuildType.OutOfSource;
  build = EsyCommands [];
  buildDev = None;
  install = NoCommands;
  patches = [];
  substs = [];
  exportedEnv = ExportedEnv.empty;
  buildEnv = StringMap.empty;
}
