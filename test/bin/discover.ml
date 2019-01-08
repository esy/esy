module C = Configurator.V1

let () =
  C.main ~name:"configure test" (fun c ->
      match C.ocaml_config_var c "system" with
      | Some "mingw64" ->
        let cmd = Bos.Cmd.(v "node" % "-p" % "require.resolve('esy-bash/package.json')") in
        begin match Bos.OS.Cmd.(run_out cmd |> to_string) with
        | Ok path ->
          C.Flags.write_lines "esy-bash.path" [path]
        | Error (`Msg msg) -> failwith msg
        end
      | _ ->
        C.Flags.write_lines "esy-bash.path" ["/not/relevant"]
  )
