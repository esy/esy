module C = Configurator.V1;

let () =
  C.main(~name="configure fastreplacestring", c => {
    let flags =
      switch (C.ocaml_config_var(c, "system")) {
      | Some("mingw64") => ["-ccopt", "-lstdc++"]
      | Some(_)
      | None => ["-ccopt", "-Ofast", "-ccopt", "-lstdc++"]
      };

    C.Flags.write_sexp("dune.flags", flags);

    let cflags = ["-lstdc++"];
    C.Flags.write_sexp("dune.cflags", cflags);

    let cxx_flags =
      switch (C.ocaml_config_var(c, "system")) {
      /* link statically on windows so we don't have to ship mingw64.dll */
      | Some("mingw64") => ["-static", "-static-libgcc", "-static-libstdc++"]
      | Some("macosx") => ["-lstdc++", "-x", "c++"]
      | Some(_)
      | None => ["-lstdc++", "-fPIC"]
      };

    C.Flags.write_sexp("dune.cxx_flags", cxx_flags);
  });
