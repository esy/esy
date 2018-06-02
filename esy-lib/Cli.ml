let pathConv =
  let open Cmdliner in
  let parse = Path.of_string in
  let print = Path.pp in
  Arg.conv ~docv:"PATH" (parse, print)

let cmdTerm ~doc ~docv =
  let open Cmdliner in
  let commandTerm =
    Arg.(non_empty & (pos_all string []) & (info [] ~doc ~docv))
  in
  let d command =
    match command with
    | [] ->
      `Error (false, "command cannot be empty")
    | tool::args ->
      let cmd = Cmd.(v tool |> addArgs args) in
      `Ok cmd
  in
  Term.(ret (const d $ commandTerm))

let cmdOptionTerm ~doc ~docv =
  let open Cmdliner in
  let commandTerm =
    Arg.(value & (pos_all string []) & (info [] ~doc ~docv))
  in
  let d command =
    match command with
    | [] ->
      `Ok None
    | tool::args ->
      let cmd = Cmd.(v tool |> addArgs args) in
      `Ok (Some cmd)
  in
  Term.(ret (const d $ commandTerm))
