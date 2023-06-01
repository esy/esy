open Esy_cmdliner

let pos f o c =
  let args = [] in
  let args = if f then "-f"::args else args in
  let args = match o with | None -> args | Some v -> "-o"::v::args in
  print_endline (String.concat "\n" (args @ ["--"] @ c))

let test_stop_on_pos =
  let f = Arg.(value & flag & info ["f"]) in
  let o = Arg.(value & opt (some string) None & info ["o"]) in
  let c = Arg.(value & pos_all string [] & info [] ~docv:"COMMAND") in
  Term.(const pos $ f $ o $ c),
  Term.info "test_stop_on_pos" ~doc:"Test stop_on_pos arguments" ~stop_on_pos:true

let () = Term.(exit @@ eval test_stop_on_pos)

