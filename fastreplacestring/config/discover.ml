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
      (* do not link statically on macos *)
      | Some "mingw64" -> [
        "-lstdc++";
        "-fno-exceptions";
        "-fno-rtti";
        ]
      | Some _
      | None -> [
          "-lstdc++";
        ]
    in
    C.Flags.write_sexp "dune.cxx_flags" cxx_flags
  )
