open Std

module PackageBuilderConfig = struct
end

type t = {
  sandboxPath : Path.t;
  storePath : Path.t;
  localStorePath : Path.t;
}

type config = t

let defaultPrefixPath = Path.v "~/.esy"

let storeInstallTree = "i"
let storeBuildTree = "b"
let storeStageTree = "s"

let storeVersion = "3"

let maxStorePaddingLength =
  (*
   * This is restricted by POSIX, Linux enforces this but macOS is more
   * forgiving.
   *)
  let maxShebangLength = 127 in
  (*
   * We reserve that amount of chars from padding so ocamlrun can be placed in
   * shebang lines
   *)
  let ocamlrunStorePath = "ocaml-n.00.000-########/bin/ocamlrun" in
  maxShebangLength
  - String.length "!#"
  - String.length (
      "/"
      ^ storeVersion
      ^ "/"
      ^ storeInstallTree
      ^ "/"
      ^ ocamlrunStorePath
    )

let create ~prefixPath sandboxPath =
  let value =
    let module Let_syntax = Result.Let_syntax in
    let initStore (path: Path.t) =
      let module Let_syntax = Result.Let_syntax in
      let%bind _ = Bos.OS.Dir.create(Path.(path / "i")) in
      let%bind _ = Bos.OS.Dir.create(Path.(path / "b")) in
      let%bind _ = Bos.OS.Dir.create(Path.(path / "s")) in
      Ok ()
    in
    let%bind prefixPath =
      match prefixPath with
      | Some v -> Ok v
      | None ->
        let%bind home = Bos.OS.Dir.user() in
        Ok Path.(home / ".esy")
    in
    let%bind sandboxPath =
      match sandboxPath with
      | Some v -> Ok v
      | None -> Bos.OS.Dir.current ()
    in
    let storePadding =
      let prefixPathLength = String.length (Fpath.to_string prefixPath) in
      let paddingLength = maxStorePaddingLength - prefixPathLength in
      String.make paddingLength '_'
    in
    let storePath = Path.(prefixPath / (storeVersion ^ storePadding)) in
    let localStorePath =
      Path.(sandboxPath / "node_modules" / ".cache" / "_esy" / "store")
    in
    let%bind () = initStore storePath in
    let%bind () = initStore localStorePath in
    Ok {
      storePath;
      sandboxPath;
      localStorePath;
    }
  in Run.liftOfBosError value

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

  val sandboxPath : t
  val storePath : t
  val localStorePath : t
end = struct

  type t = Path.t
  type ctx = config

  let sandboxPath = Path.v "%sandbox%"
  let storePath = Path.v "%store%"
  let localStorePath = Path.v "%localStore%"

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
      storePath
    else if Path.equal p config.localStorePath then
      localStorePath
    else if Path.equal p config.sandboxPath then
      sandboxPath
    else begin
      match Path.rem_prefix config.storePath p with
      | Some suffix -> Path.(storePath // suffix)
      | None -> begin match Path.rem_prefix config.localStorePath p with
        | Some suffix -> Path.(localStorePath // suffix)
        | None -> begin match Path.rem_prefix config.sandboxPath p with
          | Some suffix -> Path.(sandboxPath // suffix)
          | None -> p
        end
      end
    end

  let toString = Path.to_string

  let pp = Path.pp
  let to_yojson = Path.to_yojson

end
