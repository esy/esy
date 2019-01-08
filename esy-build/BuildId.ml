open EsyPackageConfig

module Repr = struct

  type opamcommands = {opamcommands : opamcommand list;} [@@deriving yojson]
  and opamcommand = {
    args : arg list;
    commandfilter : string option;
  } [@@deriving yojson]
  and arg = {
    arg : string;
    argfilter : string option;
  } [@@deriving yojson]

  type commands =
    | EsyCommands of CommandList.t
    | OpamCommands of opamcommands
    | NoCommands

  let commands_to_yojson = function
    | NoCommands -> `Null
    | EsyCommands commands -> CommandList.to_yojson commands
    | OpamCommands commands -> opamcommands_to_yojson commands

  let commands_of_yojson =
    let open Result.Syntax in
    function
    | `Null -> return NoCommands
    | `List _ as json ->
      let%map commands = CommandList.of_yojson json in
      EsyCommands commands
    | `Assoc _ as json ->
      let%map commands = opamcommands_of_yojson json in
      OpamCommands commands
    | _ -> error "invalid commands: expected null, list or object"

  type patch = {
    path : Path.t;
    filter : string option;
  } [@@deriving yojson]

  type t = {
    packageId : PackageId.t;
    build : build;
    platform : System.Platform.t;
    arch : System.Arch.t;
    sandboxEnv : SandboxEnv.t;
    dependencies : string list;
  } [@@deriving yojson]

  and build = {
    name : string option;
    version : Version.t option;
    mode : BuildSpec.mode;
    buildType : BuildType.t;
    buildCommands : commands;
    installCommands : commands;
    patches : patch list;
    substs : Path.t list;
    exportedEnv : ExportedEnv.t;
    buildEnv : BuildEnv.t;
  }

  let convFilter filter =
    match filter with
    | None -> None
    | Some filter -> Some (OpamFilter.to_string filter)

  let convOpamSimpleArg (simpleArg : OpamTypes.simple_arg) =
    match simpleArg with
    | OpamTypes.CString s -> Filename.quote s
    | OpamTypes.CIdent s -> s

  let convOpamArg ((simpleArg, filter) : OpamTypes.arg) =
    {arg = convOpamSimpleArg simpleArg; argfilter = convFilter filter;}

  let convOpamCommand ((args, filter) : OpamTypes.command) =
    let args = List.map ~f:convOpamArg args in
    {args; commandfilter = convFilter filter;}

  let convCommands commands =
    match commands with
    | BuildManifest.EsyCommands commands -> EsyCommands commands
    | BuildManifest.OpamCommands commands ->
      OpamCommands {opamcommands = List.map ~f:convOpamCommand commands;}
    | BuildManifest.NoCommands -> NoCommands

  let convPatch (path, filter) =
    {path; filter = Option.map ~f:OpamFilter.to_string filter}

  let convPatches patches =
    List.map ~f:convPatch patches

  let make
    ~packageId
    ~build
    ~platform
    ~arch
    ~sandboxEnv
    ~mode
    ~dependencies
    ~buildCommands
    ()
    =

    (* include ids of dependencies *)
    let dependencies = List.sort ~cmp:String.compare dependencies in

    let build =
      let {
        BuildManifest.
        name;
        version;
        buildType;
        build = _;
        buildDev = _;
        install;
        patches;
        substs;
        exportedEnv;
        buildEnv
      } = build in
      {
        name;
        version;
        buildType;
        patches = convPatches patches;
        substs;
        mode = mode;
        buildCommands = convCommands buildCommands;
        installCommands = convCommands install;
        exportedEnv = exportedEnv;
        buildEnv = buildEnv;
      }
    in

    {
      packageId;
      build;
      platform;
      arch;
      sandboxEnv;
      dependencies;
    }

  let toString repr =
    let {
      packageId;
      sandboxEnv;
      platform;
      arch;
      build;
      dependencies;
    } = repr in

    let hash =

      (* include parts of the current package metadata which contribute to the
        * build commands/environment *)
      let self =
        build
        |> build_to_yojson
        |> Yojson.Safe.to_string
      in

      let sandboxEnv =
        sandboxEnv
        |> SandboxEnv.to_yojson
        |> Yojson.Safe.to_string
      in

      String.concat "__" (
        (PackageId.show packageId)
        ::(System.Platform.show platform)
        ::(System.Arch.show arch)
        ::sandboxEnv
        ::self
        ::dependencies)
      |> Digest.string
      |> Digest.to_hex
      |> fun hash -> String.sub hash 0 8
    in

    let name = PackageId.name packageId in
    let version = PackageId.version packageId in

    match version with
    | Version.Npm _
    | Version.Opam _ ->
      Printf.sprintf "%s-%s-%s"
        (Path.safeSeg name)
        (Path.safePath (Version.show version))
        hash
    | Version.Source _ ->
      Printf.sprintf "%s-%s"
        (Path.safeSeg name)
        hash
end


type t = string

let make
  ~packageId
  ~build
  ~mode
  ~platform
  ~arch
  ~sandboxEnv
  ~dependencies
  ~buildCommands
  ()
  =
  let repr = Repr.make
    ~packageId
    ~build
    ~mode
    ~platform
    ~arch
    ~sandboxEnv
    ~dependencies
  ~buildCommands
    ()
  in
  Repr.toString repr, repr

let pp = Fmt.string
let show v = v
let compare = String.compare
let to_yojson = Json.Encode.string
let of_yojson = Json.Decode.string

module Set = StringSet
