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
  let* status =
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
  let catch = _e => {
    let tmpDir = Filename.get_temp_dir_name();
    let fileBeingCopied = path |> Fpath.to_string |> Filename.basename;
    Random.self_init();
    let suffix = Random.bits() |> string_of_int;
    let workaroundDir = Fpath.(v(tmpDir) / ("workaround-" ++ suffix));
    let workAroundFilePath = Fpath.(workaroundDir / fileBeingCopied);
    let* () = mkdir(workaroundDir);
    let* () = copyFile(path, workAroundFilePath);
    let* () = rm(path);
    let* () = copyFile(~perm=0o775, workAroundFilePath, path);
    codesign(path);
  };
  Run.try_(~catch, codesign(path));
};

let rec sign =
  fun
  | [] => return()
  | [h, ...rest] => {
      let* () = sign'(h);
      sign(rest);
    };
