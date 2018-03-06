type env = [
  (* Use current env *)
  | `CurrentEnv
  (* Use current env add some override on top *)
  | `CurrentEnvOverride of Environment.Value.t
  (* Use custom env *)
  | `CustomEnv of Environment.Value.t
]

let withProcess ?(env=`CurrentEnv) ?(resolveProgramInEnv=false) ?stdin ?stdout ?stderr cmd f =
  let open RunAsync.Syntax in

  let env = match env with
    | `CurrentEnv -> None
    | `CurrentEnvOverride env ->
      let env =
        Astring.String.Map.fold
          Astring.String.Map.add
          env
          Environment.Value.current
      in
      Some env
    | `CustomEnv env -> Some env
  in

  let%bind cmd = RunAsync.liftOfRun (
      let open Run.Syntax in
      match Bos.Cmd.to_list cmd with
      | [] -> error "empty command"
      | prg::args ->
        let%bind prg =
          match resolveProgramInEnv, env with
          | true, Some env ->
            Cmd.resolveCmdInEnv env prg
          | _ -> Ok prg
        in
        return (prg, Array.of_list (prg::args))
    ) in

  let env = Std.Option.map env ~f:(fun env -> env
                                              |> Environment.Value.M.bindings
                                              |> List.map (fun (name, value) -> name ^ "=" ^ value)
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
    | _ -> error "error running command"
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
          Environment.Value.current
      in
      Some env
    | `CustomEnv env -> Some env
  in

  let%bind cmd = RunAsync.liftOfRun (
      let open Run.Syntax in
      match Bos.Cmd.to_list cmd with
      | [] -> error "empty command"
      | prg::args ->
        let%bind prg =
          match resolveProgramInEnv, env with
          | true, Some env ->
            Cmd.resolveCmdInEnv env prg
          | _ -> Ok prg
        in
        return (prg, Array.of_list (prg::args))
    ) in

  let env = Std.Option.map env ~f:(fun env -> env
                                              |> Environment.Value.M.bindings
                                              |> List.map (fun (name, value) -> name ^ "=" ^ value)
                                              |> Array.of_list)
  in

  let f process =
    match%lwt process#status with
    | Unix.WEXITED 0 -> 
      let%lwt out = Lwt_io.read process#stdout in
      return out
    | _ -> error "error running command"
  in

  try%lwt
    Lwt_process.with_process_in ?env ?stdin ?stderr cmd f
  with
  | Unix.Unix_error (err, _, _) ->
    let msg = Unix.error_message err in
    error msg
  | _ ->
    error "error running subprocess"
