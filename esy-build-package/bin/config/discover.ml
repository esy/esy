module C = Configurator.V1

let () =
  C.main ~name:"configure fastreplacestring" (fun c ->

    let flags =
      match C.ocaml_config_var c "system" with
      | Some "mingw64" -> [
          "x86_64-w64-mingw32-g++";
          "-static";
          "-static-libgcc";
          "-static-libstdc++";
        ]
      | Some _
      | None -> [
          "g++";
        ]
    in
    C.Flags.write_lines "dune.fastreplacestring.command" flags;
  )
