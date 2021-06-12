module F = OpamFile.Dot_install;

let ( let* ) = Run.( let* );

/* This checks if we should try adding .exe extension */
let shouldTryAddExeIfNotExist =
  switch (
    Sys.getenv_opt("ESY_INSTALLER__FORCE_EXE"),
    EsyLib.System.Platform.host,
  ) {
  | (None | Some("false"), Windows) => true
  | (None | Some("false"), Linux | Darwin | Unix | Cygwin) => false
  | (None | Some("false"), Unknown) => true /* won't make it worse, I guess */
  | (Some(_), _) => true
  };

let setExecutable = perm => perm lor 0o111;
let unsetExecutable = perm => perm land lnot(0o111);

let installFile =
    (
      ~executable=false,
      ~enableLinkingOptimization,
      ~rootPath,
      ~prefixPath,
      ~dstFilename: option(Fpath.t),
      src: OpamTypes.optional(OpamTypes.basename),
    ) => {
  let srcPath = {
    let path = src.c |> OpamFilename.Base.to_string |> Fpath.v;
    if (Fpath.is_abs(path)) {
      path;
    } else {
      Fpath.(rootPath /\/ path);
    };
  };

  let dstPath =
    switch (dstFilename) {
    | None => Fpath.(prefixPath / Fpath.basename(srcPath))
    | Some(dstFilename) => Fpath.(prefixPath /\/ dstFilename)
    };

  let rec copy = (~tryAddExeIfNotExist, srcPath, dstPath) =>
    switch (Run.statIfExists(srcPath)) {
    | Ok(None) =>
      if (tryAddExeIfNotExist && !Fpath.has_ext(".exe", srcPath)) {
        let srcPath = Fpath.add_ext(".exe", srcPath);
        let dstPath = Fpath.add_ext(".exe", dstPath);
        copy(~tryAddExeIfNotExist=false, srcPath, dstPath);
      } else if (src.optional) {
        Run.return();
      } else {
        Run.errorf("source path %a does not exist", Fpath.pp, srcPath);
      }

    | Ok(Some(stats)) =>
      let origPerm = stats.Unix.st_perm;
      let perm =
        if (executable) {
          setExecutable(origPerm);
        } else {
          unsetExecutable(origPerm);
        };

      let* () = Run.mkdir(Fpath.parent(dstPath));
      let* () =
        if (enableLinkingOptimization && origPerm == perm) {
          switch (EsyLib.System.Platform.host) {
          | Windows => Run.link(~force=true, ~target=srcPath, dstPath)
          | _ => Run.symlink(~force=true, ~target=srcPath, dstPath)
          };
        } else {
          Run.copyFile(~perm, srcPath, dstPath);
        };

      Run.return();

    | Error(error) =>
      if (src.optional) {
        Run.return();
      } else {
        Error(error);
      }
    };

  copy(~tryAddExeIfNotExist=shouldTryAddExeIfNotExist, srcPath, dstPath);
};

let installSection =
    (
      ~enableLinkingOptimization,
      ~executable,
      ~makeDstFilename=?,
      ~rootPath,
      ~prefixPath,
      files,
    ) => {
  let rec aux =
    fun
    | [] => Run.return()
    | [(src, dstFilenameSpec), ...rest] => {
        let dstFilename =
          switch (dstFilenameSpec, makeDstFilename) {
          | (Some(name), _) =>
            Some(Fpath.v(OpamFilename.Base.to_string(name)))
          | (None, Some(makeDstFilename)) =>
            let src = Fpath.v(OpamFilename.Base.to_string(src.OpamTypes.c));
            Some(makeDstFilename(src));
          | (None, None) => None
          };

        let* () =
          installFile(
            ~executable,
            ~enableLinkingOptimization,
            ~rootPath,
            ~prefixPath,
            ~dstFilename,
            src,
          );
        aux(rest);
      };

  aux(files);
};

let install = (~enableLinkingOptimization, ~prefixPath, filename) => {
  let rootPath = Fpath.parent(filename);

  let* (packageName, spec) = {
    let* data = Run.read(filename);
    let packageName = Fpath.basename(Fpath.rem_ext(filename));
    let spec = {
      let filename =
        OpamFile.make(OpamFilename.of_string(Fpath.to_string(filename)));
      F.read_from_string(~filename, data);
    };

    Run.return((packageName, spec));
  };

  /* See
   *
   *   https://opam.ocaml.org/doc/2.0/Manual.html#lt-pkgname-gt-install
   *
   * for explanations on each section.
   */

  let* () =
    installSection(
      ~enableLinkingOptimization,
      ~executable=false,
      ~rootPath,
      ~prefixPath=Fpath.(prefixPath / "lib" / packageName),
      F.lib(spec),
    );

  let* () =
    installSection(
      ~enableLinkingOptimization,
      ~executable=false,
      ~rootPath,
      ~prefixPath=Fpath.(prefixPath / "lib"),
      F.lib_root(spec),
    );

  let* () =
    installSection(
      ~enableLinkingOptimization,
      ~executable=true,
      ~rootPath,
      ~prefixPath=Fpath.(prefixPath / "lib" / packageName),
      F.libexec(spec),
    );

  let* () =
    installSection(
      ~enableLinkingOptimization,
      ~executable=true,
      ~rootPath,
      ~prefixPath=Fpath.(prefixPath / "lib"),
      F.libexec_root(spec),
    );

  let* () =
    installSection(
      ~enableLinkingOptimization,
      ~executable=true,
      ~rootPath,
      ~prefixPath=Fpath.(prefixPath / "bin"),
      F.bin(spec),
    );

  let* () =
    installSection(
      ~enableLinkingOptimization,
      ~executable=true,
      ~rootPath,
      ~prefixPath=Fpath.(prefixPath / "sbin"),
      F.sbin(spec),
    );

  let* () =
    installSection(
      ~enableLinkingOptimization,
      ~executable=false,
      ~rootPath,
      ~prefixPath=Fpath.(prefixPath / "lib" / "toplevel"),
      F.toplevel(spec),
    );

  let* () =
    installSection(
      ~enableLinkingOptimization,
      ~executable=false,
      ~rootPath,
      ~prefixPath=Fpath.(prefixPath / "share" / packageName),
      F.share(spec),
    );

  let* () =
    installSection(
      ~enableLinkingOptimization,
      ~executable=false,
      ~rootPath,
      ~prefixPath=Fpath.(prefixPath / "share"),
      F.share_root(spec),
    );

  let* () =
    installSection(
      ~enableLinkingOptimization,
      ~executable=false,
      ~rootPath,
      ~prefixPath=Fpath.(prefixPath / "etc" / packageName),
      F.etc(spec),
    );

  let* () =
    installSection(
      ~enableLinkingOptimization,
      ~executable=false,
      ~rootPath,
      ~prefixPath=Fpath.(prefixPath / "doc" / packageName),
      F.doc(spec),
    );

  let* () =
    installSection(
      ~enableLinkingOptimization,
      ~executable=true,
      ~rootPath,
      ~prefixPath=Fpath.(prefixPath / "lib" / "stublibs"),
      F.stublibs(spec),
    );

  let* () = {
    let makeDstFilename = src => {
      let num = Fpath.get_ext(src);
      Fpath.(v("man" ++ num) / basename(src));
    };

    installSection(
      ~enableLinkingOptimization,
      ~executable=false,
      ~makeDstFilename,
      ~rootPath,
      ~prefixPath=Fpath.(prefixPath / "man"),
      F.man(spec),
    );
  };

  Run.return();
};
