type env =
  (* Use current env *)
  | CurrentEnv
  (* Use current env add some override on top *)
  | CurrentEnvOverride of string StringMap.t
  (* Use custom env *)
  | CustomEnv of string StringMap.t

let pp_env fmt env =
  match env with
  | CurrentEnv -> Fmt.unit "CurrentEnv" fmt ()
  | CurrentEnvOverride env ->
    Fmt.pf fmt "CustomEnvOverride %a" (Astring.String.Map.pp Fmt.(pair string string)) env
  | CustomEnv env ->
    Fmt.pf fmt "CustomEnv %a" (Astring.String.Map.pp Fmt.(pair string string)) env

let resolveCmdInEnv ~env prg =
  let path =
    let v = match StringMap.find_opt "PATH" env with
      | Some v  -> v
      | None -> ""
    in
    String.split_on_char (System.Environment.sep ()).[0] v
  in Run.ofBosError (Cmd.resolveCmd path prg)

let prepareEnv env =
  let env = match env with
    | CurrentEnv -> None
    | CurrentEnvOverride env ->
      let env =
        Astring.String.Map.fold
          Astring.String.Map.add
          env
          System.Environment.current
      in
      Some env
    | CustomEnv env -> Some env
  in
  let f env =
    let array =
      env
      |> StringMap.bindings
      |> List.map ~f:(fun (name, value) -> name ^ "=" ^ value)
      |> Array.of_list
    in
    env, array
  in
  Option.map ~f env


let withProcess ?(env=CurrentEnv) ?(resolveProgramInEnv=false) ?stdin ?stdout ?stderr cmd f =
  let open RunAsync.Syntax in

  let env = prepareEnv env in

  let%bind cmd = RunAsync.ofRun (
      let open Run.Syntax in
      let prg, args = Cmd.getToolAndArgs cmd in
      let%bind prg =
        match resolveProgramInEnv, env with
        | true, Some (env, _) ->
          resolveCmdInEnv ~env prg
        | _ -> Ok prg
      in
      return ("", Array.of_list (prg::args))
    ) in

  try%lwt
    Lwt_process.with_process_none ?env:(Option.map ~f:snd env) ?stdin ?stdout ?stderr cmd f
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
      let cmd = Cmd.show cmd in
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

let runOut ?(env=CurrentEnv) ?(resolveProgramInEnv=false) ?stdin ?stderr cmd =
  let open RunAsync.Syntax in

  (* 
  TODO Factor out this into common withProcess and use Lwt_process.with_process_in
   *)

  let env = match env with
    | CurrentEnv -> None
    | CurrentEnvOverride env ->
      let env =
        Astring.String.Map.fold
          Astring.String.Map.add
          env
          System.Environment.current
      in
      Some env
    | CustomEnv env -> Some env
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
