type env = [
  (* Use current env *)
  | `CurrentEnv
  (* Use current env add some override on top *)
  | `CurrentEnvOverride of string StringMap.t
  (* Use custom env *)
  | `CustomEnv of string StringMap.t
]

let currentEnv =
  let parse item =
    let idx = String.index item '=' in
    let name = String.sub item 0 idx in
    let value = String.sub item (idx + 1) (String.length item - idx - 1) in
    name, value
  in
  (* Filter bash function which are being exported in env *)
  let filter (name, _value) =
    let starting = "BASH_FUNC_" in
    let ending = "%%" in
    not (
      String.length name > String.length starting
      && Str.first_chars name (String.length starting) = starting
      && Str.last_chars name (String.length ending) = ending
    )
  in
  let build env (name, value) =
    if filter (name, value)
    then StringMap.add name value env
    else env
  in
  Unix.environment ()
  |> Array.map parse
  |> Array.fold_left build StringMap.empty

let resolveCmdInEnv ~env prg =
  let path =
    let v = match StringMap.find_opt "PATH" env with
      | Some v  -> v
      | None -> ""
    in
    String.split_on_char System.Environment.sep.[0] v
  in Run.ofBosError (Cmd.resolveCmd path prg)

let withProcess ?(env=`CurrentEnv) ?(resolveProgramInEnv=false) ?stdin ?stdout ?stderr cmd f =
  let open RunAsync.Syntax in

  let env = match env with
    | `CurrentEnv -> None
    | `CurrentEnvOverride env ->
      let env =
        Astring.String.Map.fold
          Astring.String.Map.add
          env
          currentEnv
      in
      Some env
    | `CustomEnv env -> Some env
  in

  let%bind cmd = RunAsync.ofRun (
      let open Run.Syntax in
      let prg, args = Cmd.getToolAndArgs cmd in
      let%bind prg =
        match resolveProgramInEnv, env with
        | true, Some env ->
          resolveCmdInEnv ~env prg
        | _ -> Ok prg
      in
      return ("", Array.of_list (prg::args))
    ) in

  let env = Option.map env ~f:(fun env -> env
                                              |> StringMap.bindings
                                              |> List.map ~f:(fun (name, value) -> name ^ "=" ^ value)
                                              |> Array.of_list)
  in

  try%lwt
    Lwt_process.with_process_none ?env ?stdin ?stdout ?stderr cmd f
  with
  | Unix.Unix_error (err, _, _) ->
    let msg = Unix.error_message err in
    error msg
  | _ ->
    error "error running subprocess"


let run ?env ?resolveProgramInEnv ?stdin ?stdout ?stderr cmd =
  let open RunAsync.Syntax in
  let f process =
    match%lwt process#status with
    | Unix.WEXITED 0 -> return ()
    | _ ->
      let cmd = Cmd.toString cmd in
      let msg = Printf.sprintf "error running command: %s" cmd in
      error msg
  in
  withProcess ?env ?resolveProgramInEnv ?stdin ?stdout ?stderr cmd f

let runToStatus ?env ?resolveProgramInEnv ?stdin ?stdout ?stderr cmd =
  let open RunAsync.Syntax in
  let f process =
    let%lwt status = process#status in
    return status
  in
  withProcess ?env ?resolveProgramInEnv ?stdin ?stdout ?stderr cmd f

let runOut ?(env=`CurrentEnv) ?(resolveProgramInEnv=false) ?stdin ?stderr cmd =
  let open RunAsync.Syntax in

  (* 
  TODO Factor out this into common withProcess and use Lwt_process.with_process_in
   *)

  let env = match env with
    | `CurrentEnv -> None
    | `CurrentEnvOverride env ->
      let env =
        Astring.String.Map.fold
          Astring.String.Map.add
          env
          currentEnv
      in
      Some env
    | `CustomEnv env -> Some env
  in

  let%bind cmdLwt = RunAsync.ofRun (
      let open Run.Syntax in
      let prg, args = Cmd.getToolAndArgs cmd in
      let%bind prg =
        match resolveProgramInEnv, env with
        | true, Some env ->
          resolveCmdInEnv ~env prg
        | _ -> Ok prg
      in
      return (prg, Array.of_list (prg::args))
    ) in

  let env = Option.map env ~f:(fun env -> env
                                              |> StringMap.bindings
                                              |> List.map ~f:(fun (name, value) -> name ^ "=" ^ value)
                                              |> Array.of_list)
  in

  let f process =
    let%lwt out = Lwt.finalize
      (fun () -> Lwt_io.read process#stdout)
      (fun () -> Lwt_io.close process#stdout)
    in
    match%lwt process#status with
    | Unix.WEXITED 0 -> return out
    | _ ->
      let msg = Printf.sprintf "running command: %s" (Cmd.show cmd) in
      error msg
  in

  try%lwt
    Lwt_process.with_process_in ?env ?stdin ?stderr cmdLwt f
  with
  | Unix.Unix_error (err, _, _) ->
    let msg = Unix.error_message err in
    error msg
  | _ ->
    error "error running subprocess"
