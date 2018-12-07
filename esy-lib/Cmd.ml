(*
 * Tool and a reversed list of args.
 *
 * We store args reversed so we allow an efficient append.
 *
 * XXX: It is important we do List.rev at the boundaries so we don't get a
 * reversed argument order.
 *)
type t = string * string list
  [@@deriving ord]

let v tool = tool, []

let ofPath path = v (Path.show path)

let p = Path.show

let addArg arg (tool, args) =
  let args = arg::args in
  tool, args

let addArgs nargs (tool, args) =
  let args =
    let f args arg = arg::args in
    List.fold_left ~f ~init:args nargs
  in
  tool, args

let (%) (tool, args) arg =
  let args = arg::args in
  tool, args

let getToolAndArgs (tool, args) =
  let args = List.rev args in
  tool, args

let ofToolAndArgs (tool, args) =
  let args = List.rev args in
  tool, args

let getToolAndLine (tool, args) =
  let args = List.rev args in
  (* On Windows, we need the tool to be the empty string to use path resolution *)
  (* More info here: http://ocsigen.org/lwt/3.2.1/api/Lwt_process *)
  match System.Platform.host with
  | Windows -> "", Array.of_list (tool::args)
  | _ -> tool, Array.of_list (tool::args)

let getTool (tool, _args) = tool

let getArgs (_tool, args) = List.rev args

let mapTool f (tool, args) =
  (f tool, args)

let show (tool, args) =
  let tool = Filename.quote tool in
  let args = List.rev_map ~f:Filename.quote args in
  StringLabels.concat ~sep:" " (tool::args)

let pp ppf (tool, args) =
  match args with
  | [] -> Fmt.(pf ppf "%s" tool)
  | args ->
    let args = List.rev args in
    let line = List.map ~f:Filename.quote (tool::args) in
    Fmt.(pf ppf "@[<h>%a@]" (list ~sep:sp string) line)

let isExecutable (stats : Unix.stats) =
  let userExecute = 0b001000000 in
  let groupExecute = 0b000001000 in
  let othersExecute = 0b000000001 in
  (userExecute lor groupExecute lor othersExecute) land stats.Unix.st_perm <> 0

(*
 * When running from some contexts, like the ChildProcess, only the system paths are provided.
 * However, on Windows, we also need to check the equivalent of the `bin` and `usr/bin` folders,
 * as shell commands are provided there (these paths get converted to their cygwin equivalents and checked).
 *)
let getAdditionalResolvePaths path =
    match System.Platform.host with
    | Windows -> path @ ["/bin"; "/usr/bin"]
    | _ -> path

let getPotentialExtensions =
    match System.Platform.host with
    | Windows ->
      (* TODO(andreypopp): Consider using PATHEXT env variable here. *)
      [""; ".exe"; ".cmd"]
    | _ -> [""]

let checkIfExecutable path =
    let open Result.Syntax in
    match System.Platform.host with
    (* Windows has a different file policy model than Unix - matching with the Unix permissions won't work *)
    (* In particular, the Unix.stat implementation emulates this on Windows by checking the extension for `exe`/`com`/`cmd`/`bat` *)
    (* But in our case, since we're deferring to the Cygwin layer, it's possible to have executables that don't confirm to that rule *)
    | Windows ->
        let%bind exists = Bos.OS.Path.exists path in
        begin match exists with
        | true -> Ok (Some path)
        | _ -> Ok None
        end
    | _ ->
        let%bind stats = Bos.OS.Path.stat path in
        begin match stats.Unix.st_kind, isExecutable stats with
        | Unix.S_REG, true -> Ok (Some path)
        | _ -> Ok None
        end

let checkIfCommandIsAvailable fullPath =
    let extensions = getPotentialExtensions in
    let evaluate prev next =
        match prev with
        | Ok (Some (x)) -> Ok (Some (x))
        | _ -> 
            let pathToTest = (Fpath.to_string fullPath) ^ next in
            let p = Fpath.v pathToTest in
            checkIfExecutable p
    in
    List.fold_left ~f:evaluate ~init:(Ok None) extensions

let resolveCmd path cmd =
  let open Result.Syntax in
  let allPaths = getAdditionalResolvePaths path in
  let find p =
    let p = Path.(v p / cmd) in
    let p = EsyBash.normalizePathForWindows p in
    checkIfCommandIsAvailable p
    in
  let rec resolve =
    function
    | [] ->
      Error (`Msg ("unable to resolve command: " ^ cmd))
    | ""::xs -> resolve xs
    | x::xs ->
      begin match find x with
      | Ok (Some (x)) ->
        Ok (Path.show x)
      | Ok None
      | Error _ -> resolve xs
      end
  in
  match cmd.[0] with
  | '.'
  | '/' -> Ok cmd
  | _ ->
    let isSep = function
      | '/' -> true
      | '\\' -> true
      | _ -> false
    in
    if Astring.String.exists isSep cmd
    then return cmd
    else resolve allPaths

let resolveInvocation path (tool, args) =
  let open Result.Syntax in
  let%bind tool = resolveCmd path tool in
  return (tool, args)

let toBosCmd cmd =
  let tool, args = getToolAndArgs cmd in
  Bos.Cmd.of_list (tool::args)

let ofBosCmd cmd =
  match Bos.Cmd.to_list cmd with
  | [] -> Error (`Msg "empty command")
  | tool::args -> Ok (tool, List.rev args)

let ofListExn = function
  | [] -> raise (Invalid_argument "empty command")
  | tool::args -> v tool |> addArgs args
