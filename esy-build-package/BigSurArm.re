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
  let%bind status =
    run_status(
      ~quiet=true,
      Cmd.(
        v("codesign")
        % "--sign"
        % "-"
        % "--force"
        % "--preserve-metadata=entitlements,requirements,flags,runtime"
        % p(fpath)
      ),
    );
  switch (status) {
  | `Exited(exitCode) =>
    if (exitCode != 0) {
      errorf(
        "codesigning %s failed with exit code %d",
        Fpath.to_string(fpath),
        exitCode,
      );
    } else {
      return();
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
  let%bind () = codesign(path);
  let tmpDir = Filename.get_temp_dir_name();
  let fileBeingCopied = path |> Fpath.to_string |> Filename.basename;
  let workAroundFilePath = Fpath.(v(tmpDir) / "workaround" / fileBeingCopied);
  let%bind () = mkdir(Fpath.(v(tmpDir) / "workaround"));
  let%bind () = copyFile(path, workAroundFilePath);
  let%bind () = rm(path);
  let%bind () = copyFile(~perm=0o775, workAroundFilePath, path);
  codesign(path);
};

let rec sign =
  fun
  | [] => return()
  | [h, ...rest] => {
      let%bind () = sign'(h);
      sign(rest);
    };
