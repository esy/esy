let stripComponentFrom = (~stripComponents=?, out) => {
  open RunAsync.Syntax;
  let rec find = path =>
    fun
    | 0 => return(path)
    | n =>
      switch%bind (Fs.listDir(path)) {
      | [item] => find(Path.(path / item), n - 1)
      | [] => error("unpacking: unable to strip path components: empty dir")
      | _ =>
        let%lwt () =
          Esy_logs_lwt.info(m =>
            m(
              "unpacking: unable to strip path components: multiple root dirs",
            )
          );
        return(path);
      };
  /* Strip components was greater than 0, but the tarball has multiple entires in the root
     to traverse deep.
     Package that caused this: https://github.com/project-everest/hacl-star/releases/download/ocaml-v0.3.0/hacl-star.0.3.0.tar.gz
     PR: https://github.com/esy/esy/pull/1236
     Bailing out and returning root... */

  switch (stripComponents) {
  | None => return(out)
  | Some(n) => find(out, n)
  };
};

let copyAll = (~src, ~dst, ()) => {
  open RunAsync.Syntax;
  let* items = Fs.listDir(src);
  let* () = Fs.createDir(dst);
  let f = item => Fs.copyPath(~src=Path.(src / item), ~dst=Path.(dst / item));
  RunAsync.List.processSeq(~f, items);
};

let run = cmd => {
  let f = p => {
    let%lwt stdout = Lwt_io.read(p#stdout)
    and stderr = Lwt_io.read(p#stderr);
    switch%lwt (p#status) {
    | Unix.WEXITED(0) => RunAsync.return()
    | _ =>
      let%lwt () =
        Esy_logs_lwt.err(m =>
          m(
            "@[<v>command failed: %a@\nstderr:@[<v 2>@\n%a@]@\nstdout:@[<v 2>@\n%a@]@]",
            Cmd.pp,
            cmd,
            Fmt.lines,
            stderr,
            Fmt.lines,
            stdout,
          )
        );
      RunAsync.error("error running command");
    };
  };

  try%lwt(EsyBashLwt.with_process_full(cmd, f)) {
  | [@implicit_arity] Unix.Unix_error(err, _, _) =>
    let msg = Unix.error_message(err);
    RunAsync.error(msg);
  | _ => RunAsync.error("error running subprocess")
  };
};

let fixFilePermissionsAfterUnTar = out => {
  let umask = lnot(System.getumask());
  Fs.traverse(
    ~f=
      (p, s) => {
        let p = EsyBash.normalizePathForCygwin(Path.show(p));
        try%lwt(
          switch (s.st_kind) {
          | Unix.S_DIR =>
            let%lwt () = Lwt_unix.chmod(p, s.st_perm lor 0o755 land umask);
            RunAsync.return();
          | _ => RunAsync.return()
          }
        ) {
        | _ => RunAsync.return()
        };
      },
    out,
  );
};

let unpackWithTar = (~stripComponents=?, ~dst, filename) => {
  open RunAsync.Syntax;
  let unpack = out => {
    let* cmd =
      RunAsync.ofBosError(
        {
          open Result.Syntax;
          let nf = EsyBash.normalizePathForCygwin(Path.show(filename));
          let normalizedOut = EsyBash.normalizePathForCygwin(Path.show(out));
          return(Cmd.(v("tar") % "xf" % nf % "-C" % normalizedOut));
        },
      );

    run(cmd);
  };

  switch (stripComponents) {
  | Some(stripComponents) =>
    Fs.withTempDir(out => {
      let* () = unpack(out);
      // Only in case of Linux & OSX fix file permissions
      let* () =
        System.Platform.isWindows
          ? RunAsync.return() : fixFilePermissionsAfterUnTar(out);
      let* out = stripComponentFrom(~stripComponents, out);
      copyAll(~src=out, ~dst, ());
    })
  | None => unpack(dst)
  };
};

let unpackWithUnzip = (~stripComponents=?, ~dst, filename) => {
  open RunAsync.Syntax;
  let unpack = out =>
    run(Cmd.(v("unzip") % "-q" % "-d" % p(out) % p(filename)));
  switch (stripComponents) {
  | Some(stripComponents) =>
    Fs.withTempDir(out => {
      let* () = unpack(out);
      let* out = stripComponentFrom(~stripComponents, out);
      copyAll(~src=out, ~dst, ());
    })
  | None => unpack(dst)
  };
};

let zipHeader =
  /*
   * From https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT
   *
   *   0x50 0x4b 0x03 0x04
   *
   */
  Int32.of_string("67324752");

let checkIfZip = filename => {
  let checkZipHeader = ic => {
    let%lwt v = Lwt_io.read_int32(ic);
    Lwt.return(Int32.compare(v, zipHeader) == 0);
  };

  try%lwt({
    let buffer = Lwt_bytes.create(16);
    Lwt_io.(
      with_file(~buffer, ~mode=Input, Path.show(filename), checkZipHeader)
    );
  }) {
  | _ => Lwt.return(false)
  };
};

let unpack = (~stripComponents=?, ~dst, filename) =>
  switch (Path.getExt(~multi=true, filename)) {
  | ".gz"
  | ".tar"
  | ".tar.gz"
  | ".tar.bz2" => unpackWithTar(~stripComponents?, ~dst, filename)
  | ".zip" => unpackWithUnzip(~stripComponents?, ~dst, filename)
  | _ =>
    if%lwt (checkIfZip(filename)) {
      unpackWithUnzip(~stripComponents?, ~dst, filename);
    } else {
      unpackWithTar(~stripComponents?, ~dst, filename);
    }
  };

let create = (~filename, ~outpath=".", src) =>
  RunAsync.ofBosError(
    {
      open Result.Syntax;
      let nf = EsyBash.normalizePathForCygwin(Path.show(filename));
      let ns = EsyBash.normalizePathForCygwin(Path.show(src));
      let cmd = Cmd.(v("tar") % "czf" % nf % "-C" % ns % outpath);
      let* res = EsyBash.run(Cmd.toBosCmd(cmd));
      return(res);
    },
  );
