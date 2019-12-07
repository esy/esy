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
        error(
          "unpacking: unable to strip path components: multiple root dirs",
        )
      };

  switch (stripComponents) {
  | None => return(out)
  | Some(n) => find(out, n)
  };
};

let copyAll = (~src, ~dst, ()) => {
  open RunAsync.Syntax;
  let%bind items = Fs.listDir(src);
  let%bind () = Fs.createDir(dst);
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
        Logs_lwt.err(m =>
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

let unpackWithTar = (~stripComponents=?, ~dst, filename) => {
  open RunAsync.Syntax;
  let unpack = out => {
    let%bind cmd =
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
      let%bind () = unpack(out);
      let%bind out = stripComponentFrom(~stripComponents, out);
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
      let%bind () = unpack(out);
      let%bind out = stripComponentFrom(~stripComponents, out);
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
      let%bind res = EsyBash.run(Cmd.toBosCmd(cmd));
      return(res);
    },
  );
