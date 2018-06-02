type t =
  Bos.Cmd.t
  [@@deriving (show, eq, ord)]

let toList = Bos.Cmd.to_list

let v = Bos.Cmd.v
let p = Bos.Cmd.p

let add = Bos.Cmd.add_args
let addArg arg cmd = Bos.Cmd.add_arg cmd arg
let addArgs args cmd = Bos.Cmd.(cmd %% of_list args)

let (%) = Bos.Cmd.(%)
let (%%) = Bos.Cmd.(%%)

let getToolAndArgs cmd =
  match Bos.Cmd.to_list cmd with
  | tool::args -> tool, args
  | [] -> assert false

let getTool cmd =
  match Bos.Cmd.to_list cmd with
  | tool::_ -> tool
  | [] -> assert false

let getArgs cmd =
  match Bos.Cmd.to_list cmd with
  | _::args -> args
  | [] -> assert false

let toString = Bos.Cmd.to_string
let pp = Bos.Cmd.pp

let isExecutable (stats : Unix.stats) =
  let userExecute = 0b001000000 in
  let groupExecute = 0b000001000 in
  let othersExecute = 0b000000001 in
  (userExecute lor groupExecute lor othersExecute) land stats.Unix.st_perm <> 0

let resolveCmd path cmd =
  let open Result.Syntax in
  let find p =
    let p = let open Path in (v p) / cmd in
    let%bind stats = Bos.OS.Path.stat p in
    match stats.Unix.st_kind, isExecutable stats with
    | Unix.S_REG, true -> Ok (Some p)
    | _ -> Ok None
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

let resolveInvocation path cmd =
  let open Result.Syntax in
  match toList cmd with
  | [] ->
    Error (`Msg ("empty command"))
  | cmd::args ->
    let%bind cmd = resolveCmd path cmd in
    Ok (Bos.Cmd.of_list (cmd :: args))

let toBosCmd cmd = cmd
let ofBosCmd cmd = cmd
