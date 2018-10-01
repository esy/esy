module C = Configurator.V1

let () =
  C.main ~name:"configure fastreplacestring" (fun c ->

    let flags =
      match C.ocaml_config_var c "system" with
      (* do not link statically on macos *)
      | Some "macosx" -> [
          "-ccopt"; "-Ofast";
          "-ccopt"; "-lstdc++";
        ]
      | Some "mingw64" -> [
          "-ccopt"; "-lstdc++";
          "-ccopt"; "-link -static";
          "-ccopt"; "-link -static-libgcc";
          "-ccopt"; "-link -static-libstdc++";
        ]
      | Some _
      | None -> [
          "-ccopt"; "-Ofast";
          "-ccopt"; "-lstdc++";
          "-ccopt"; "-link -static";
          "-ccopt"; "-link -static-libgcc";
          "-ccopt"; "-link -static-libstdc++";
        ]
    in
    C.Flags.write_sexp "dune.flags" flags;

    let cxx_flags =
      match C.ocaml_config_var c "system" with
      (* do not link statically on macos *)
      | Some "macosx" -> [
        "-lstdc++";
        "-fno-exceptions";
        "-fno-rtti";
        ]
      | Some _
      | None -> [
        "-lstdc++";
        "-fno-exceptions";
        "-fno-rtti";
        "-static";
        "-static-libgcc";
        "-static-libstdc++";
        ]
    in
    C.Flags.write_sexp "dune.cxx_flags" cxx_flags
  )
