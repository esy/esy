module C = Configurator.V1

let () =
  C.main ~name:"configure fastreplacestring" (fun c ->

    let flags =
      match C.ocaml_config_var c "system" with
      | Some "mingw64" -> [
          "-ccopt"; "-lstdc++";
        ]
      | Some _
      | None -> [
          "-ccopt"; "-Ofast";
          "-ccopt"; "-lstdc++";
        ]
    in
    C.Flags.write_sexp "dune.flags" flags;

    let cxx_flags =
      match C.ocaml_config_var c "system" with
      (* link statically on windows so we don't have to ship mingw64.dll *)
      | Some "mingw64" -> [
        "-static";
        "-static-libgcc";
        "-static-libstdc++";
        ]
      | Some "macosx" -> [
          "-lstdc++";
          "-x"; "c++";
        ]
      | Some _
      | None -> [
          "-lstdc++";
        ]
    in
    C.Flags.write_sexp "dune.cxx_flags" cxx_flags
  )
