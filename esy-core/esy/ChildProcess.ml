let withProcess ?env ?stdin ?stdout ?stderr ?(resolveProgramInEnv=false) cmd f =
  let open RunAsync.Syntax in

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

  Lwt_process.with_process_none ?env ?stdin ?stdout ?stderr cmd f

let run ?env ?resolveProgramInEnv ?stdin ?stdout ?stderr cmd =
  let open RunAsync.Syntax in
  let f process =
    match%lwt process#status with
    | Unix.WEXITED 0 -> return ()
    | _ -> error "error running command"
  in
  withProcess ?env ?resolveProgramInEnv ?stdin ?stdout ?stderr cmd f
