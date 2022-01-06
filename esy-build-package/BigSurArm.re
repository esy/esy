open Run;
open Bos.OS.Cmd;
/*
 Executables, once tampered with, need to be resigned on BigSur (arm64)
 Ideally, it should be as simple as,

 $ codesign --sign - --force --preserve-metadata=<...properties> /path/to/binary

 However, due to bug in the tool, codesign, the following error is thrown.

 ```
 the codesign_allocate helper tool cannot be found or used
 ```

 (not sure where this is tracked. Ref: https://github.com/Homebrew/brew/issues/9082#issuecomment-727247739)

 To workaround this, interim fix suggested by Homebrew team is to copy the binary to a different folder, and mv it back destroying the original file's inode.

 [sign'] does exactly that. */

let codesign = fpath => {
  let* (outputString, (_runInfo, status)) =
    run_out(
      ~err=err_run_out,
      Cmd.(
        v("codesign")
        % "--sign"
        % "-"
        % "--force"
        % "--preserve-metadata=entitlements,requirements,flags,runtime"
        % p(fpath)
      ),
    )
    |> out_string;
  switch (status) {
  | `Exited(exitCode) =>
    switch (exitCode) {
    | 0 => return()
    | 1 =>
      if (Str.search_forward(
            Str.regexp("Permission denied"),
            outputString,
            0,
          )
          != (-1)) {
        print_newline();
        print_newline();
        print_endline(
          "# esy-build-package: codesigning failed due to insufficient permission. Re-running with sudo",
        );
        let* (outputString, (_runInfo, status)) =
          run_out(
            ~err=err_run_out,
            Cmd.(
              v("sudo")
              % "codesign"
              % "--sign"
              % "-"
              % "--force"
              % "--preserve-metadata=entitlements,requirements,flags,runtime"
              % p(fpath)
            ),
          )
          |> out_string;
        switch (status) {
        | `Exited(exitCode) =>
          switch (exitCode) {
          | 0 => return()
          | exitCode =>
            errorf(
              "codesigning %s failed with exit code %d",
              Fpath.to_string(fpath),
              exitCode,
            )
          }
        | `Signaled(signal) =>
          errorf(
            "codesigning %s killed by signal %d",
            Fpath.to_string(fpath),
            signal,
          )
        };
      } else {
        errorf(
          "codesigning %s failed with exit code %d\n Stdout and stderr %s",
          Fpath.to_string(fpath),
          exitCode,
          outputString,
        );
      }
    | exitCode =>
      errorf(
        "codesigning %s failed with exit code %d",
        Fpath.to_string(fpath),
        exitCode,
      )
    }
  | `Signaled(signal) =>
    errorf(
      "codesigning %s killed by signal %d",
      Fpath.to_string(fpath),
      signal,
    )
  };
};

let sign' = path => {
  let* () = codesign(path);
  let tmpDir = Filename.get_temp_dir_name();
  let fileBeingCopied = path |> Fpath.to_string |> Filename.basename;
  let workAroundFilePath = Fpath.(v(tmpDir) / "workaround" / fileBeingCopied);
  let* () = mkdir(Fpath.(v(tmpDir) / "workaround"));
  let* () = copyFile(path, workAroundFilePath);
  let* () = rm(path);
  let* () = copyFile(~perm=0o775, workAroundFilePath, path);
  codesign(path);
};

let rec sign =
  fun
  | [] => return()
  | [h, ...rest] => {
      let* () = sign'(h);
      sign(rest);
    };
