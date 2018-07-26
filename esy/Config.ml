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
      let%bind storePadding = Store.getPadding prefixPath in
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

module type ABSTRACT_STRING = sig
  type t
  type ctx

  val show : t -> string
  val pp : t Fmt.t

  val equal : t -> t -> bool
  val compare : t -> t -> int

  val to_yojson : t Json.encoder
  val of_yojson : t Json.decoder
end

module type ABSTRACT_PATH = sig
  include ABSTRACT_STRING

  val (/) : t -> string -> t
  val ofPath : ctx -> Path.t -> t
  val toPath : ctx -> t -> Path.t
end

module Value : sig
  include ABSTRACT_STRING with type ctx = t

  val v : string -> t

  val toString : ctx -> t -> string
  val ofString : ctx -> string -> t

end = struct

  type t = string
  type ctx = config

  let v v = v

  let sandboxRe = Str.regexp "%sandbox%"
  let storeRe = Str.regexp "%store%"
  let localStoreRe = Str.regexp "%localStore%"

  let toString config v =
    v
    |> Str.global_replace sandboxRe (Path.toString config.sandboxPath)
    |> Str.global_replace storeRe (Path.toString config.storePath)
    |> Str.global_replace localStoreRe (Path.toString config.localStorePath)

  let ofString config v =
    let sandboxRe = Str.regexp (Path.toString config.sandboxPath) in
    let storeRe = Str.regexp (Path.toString config.storePath) in
    let localStoreRe = Str.regexp (Path.toString config.localStorePath) in
    v
    |> Str.global_replace sandboxRe "%sandbox%"
    |> Str.global_replace storeRe "%store%"
    |> Str.global_replace localStoreRe "%localStore%"

  let show v = v
  let pp = Fmt.string
  let to_yojson v = `String v
  let of_yojson = Json.Parse.string
  let equal = String.equal
  let compare = String.compare
end

module Path : sig
  include ABSTRACT_PATH with type ctx = t

  val v : string -> t
  val toValue : t -> Value.t

  val sandbox : t
  val store : t
  val localStore : t
end = struct

  type t = Path.t
  type ctx = config

  let v v = Path.v v

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

  let toValue v =
    v |> Path.toString |> EsyLib.Path.normalizePathSlashes |> Value.v

  let show = Path.show

  let pp = Path.pp
  let to_yojson = Path.to_yojson
  let of_yojson = Path.of_yojson
  let equal = Path.equal
  let compare = Path.compare
end
