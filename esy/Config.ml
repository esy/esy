module Store = EsyLib.Store

type t = {
  esyVersion : string;
  sandboxPath : Path.t;
  prefixPath : Path.t;
  storePath : Path.t;
  localStorePath : Path.t;
  fastreplacestringCommand : Cmd.t;
  esyBuildPackageCommand : Cmd.t;
  esyInstallJsCommand : string;
}

type config = t

let defaultPrefixPath = Path.v "~/.esy"

let initStore (path: Path.t) =
  let open Result.Syntax in
  let%bind _ = Bos.OS.Dir.create(Path.(path / "i")) in
  let%bind _ = Bos.OS.Dir.create(Path.(path / "b")) in
  let%bind _ = Bos.OS.Dir.create(Path.(path / "s")) in
  Ok ()

let create
  ~fastreplacestringCommand
  ~esyBuildPackageCommand
  ~esyInstallJsCommand
  ~esyVersion
  ~prefixPath (sandboxPath : Path.t) =
  let value =
    let open Result.Syntax in

    let%bind prefixPath =
      match prefixPath with
      | Some v -> Ok v
      | None ->
        let%bind home = Bos.OS.Dir.user() in
        Ok Path.(home / ".esy")
    in

    let%bind storePath =
      let storePadding = Store.getPadding prefixPath in
      Ok Path.(prefixPath / (Store.version ^ storePadding))
    in
    let localStorePath =
      Path.(sandboxPath / "node_modules" / ".cache" / "_esy" / "store")
    in
    let storeLinkPath =
      Path.(prefixPath / Store.version)
    in

    let%bind () = initStore storePath in
    let%bind () = initStore localStorePath in
    let%bind () = if%bind Bos.OS.Path.exists storeLinkPath
      then Ok ()
      else Bos.OS.Path.symlink ~target:storePath storeLinkPath
    in Ok {
      esyVersion;
      prefixPath;
      storePath;
      sandboxPath;
      localStorePath;
      fastreplacestringCommand;
      esyBuildPackageCommand;
      esyInstallJsCommand;
    }
  in
  value |> Run.ofBosError |> RunAsync.ofRun

module type ABSTRACT_PATH = sig
  (**
   * Path.
   *)
  type t

  (** Path context, some opaque data which path relies on to be resolved into
   * real path.
   *)
  type ctx

  (**
   * Build a new path by appending a segment.
   *)
  val (/) : t -> string -> t

  (**
   * Encode a real path into an abstract path given the context.
   *)
  val ofPath : ctx -> Path.t -> t

  (**
   * Resolve an abstract path into a real path given the context.
   *)
  val toPath : ctx -> t -> Path.t

  val toString : t -> string

  val pp : Format.formatter -> t -> unit
  val to_yojson : t -> Yojson.Safe.json
  val equal : t -> t -> bool
  val compare : t -> t -> int
end

(**
 * Path relative to config's sandboxPath, storePath or localStorePath.
 *
 * Such paths are relocatable across different sandboxes and even machines.
 *
 * We don't enforce it yet fully (ofPath can't fail) but it's nice not to forget
 * to decode them into real paths before use.
 *
 * TODO: consider making ofPath to return a result
 *)
module ConfigPath : sig
  include ABSTRACT_PATH with type ctx = t

  val sandbox : t
  val store : t
  val localStore : t
end = struct

  type t = Path.t
  type ctx = config

  let sandbox = Path.v "%sandbox%"
  let store = Path.v "%store%"
  let localStore = Path.v "%localStore%"

  let (/) a b = Path.(a / b)

  let toPath config p =
    let env = function
      | "sandbox" -> Some (Path.to_string config.sandboxPath)
      | "store" -> Some (Path.to_string config.storePath)
      | "localStore" -> Some (Path.to_string config.localStorePath)
      | _ -> None
    in
    let path = EsyBuildPackage.PathSyntax.renderExn env (Path.to_string p) in
    match Path.of_string path with
    | Ok path -> path
    | Error (`Msg msg) ->
      (* FIXME: really should be fixed by ofPath returning result (validating) *)
      failwith msg

  let cwd = Path.v (Sys.getcwd ())

  let ofPath config p =
    let p = if Path.is_abs p then p else Path.(cwd // p) in
    let p = Path.normalize p in
    if Path.equal p config.storePath then
      store
    else if Path.equal p config.localStorePath then
      localStore
    else if Path.equal p config.sandboxPath then
      sandbox
    else begin
      match Path.rem_prefix config.storePath p with
      | Some suffix -> Path.(store // suffix)
      | None -> begin match Path.rem_prefix config.localStorePath p with
        | Some suffix -> Path.(localStore // suffix)
        | None -> begin match Path.rem_prefix config.sandboxPath p with
          | Some suffix -> Path.(sandbox // suffix)
          | None -> p
        end
      end
    end

  let toString = Path.to_string

  let pp = Path.pp
  let to_yojson = Path.to_yojson
  let equal = Path.equal
  let compare = Path.compare

end
