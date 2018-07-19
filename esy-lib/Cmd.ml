(*
 * Tool and a reversed list of args.
 *
 * We store args reversed so we allow an efficient append.
 *
 * XXX: It is important we do List.rev at the boundaries so we don't get a
 * reversed argument order.
 *)
type t = string * string list
  [@@deriving (eq, ord)]

let v tool = tool, []
let p = Path.toString

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

let getToolAndLine (tool, args) =
  let args = List.rev args in
  tool, Array.of_list (tool::args)

let getTool (tool, _args) = tool

let getArgs (_tool, args) = List.rev args

let toString (tool, args) =
  let tool = Filename.quote tool in
  let args = List.rev_map ~f:Filename.quote args in
  StringLabels.concat ~sep:" " (tool::args)

let show = toString

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

let getPotentialExtensions =
    match System.Platform.host with
    | Windows -> [""; ".exe"]
    | _ -> [""]

let checkIfCommandIsAvailable fullPath =
    let open Result.Syntax in
    let isExecutable p = 
        let%bind stats = Bos.OS.Path.stat p in
        match stats.Unix.st_kind, isExecutable stats with
        | Unix.S_REG, true -> Ok (Some p)
        | _ -> Ok None
    in
    let extensions = getPotentialExtensions in
    let evaluate prev next =
        match prev with
        | Ok (Some (x)) -> Ok (Some (x))
        | _ -> 
            let pathToTest = (Fpath.to_string fullPath) ^ next in
            let p = Fpath.v pathToTest in
            isExecutable p
    in
    List.fold_left ~f:evaluate ~init:(Ok None) extensions

let resolveCmd path cmd =
  let open Result.Syntax in
  let find p =
    let p = let open Path in (v p) / cmd in
    let%bind p = EsyBash.normalizePathForWindows p in
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
        Ok (Path.toString x)
      | Ok None
      | Error _ -> resolve xs
      end
  in
  match cmd.[0] with
  | '.'
  | '/' -> Ok cmd
  | _ -> resolve path

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
