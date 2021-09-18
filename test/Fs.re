include EsyLib.Curl;

module RunAsync = EsyLib.RunAsync;
module Fs = EsyLib.Fs;
module Path = EsyLib.Path;
module System = EsyLib.System;

let%test "copyPathLwt - copy simple file" = {
  let test = () => {
    let f = tempPath => {
      open RunAsync.Syntax;
      let src = Path.(tempPath / "src.txt");
      let dst = Path.(tempPath / "dst.txt");
      let data = "test";
      let* () = Fs.createDir(tempPath);
      let* () = Fs.writeFile(~data, src);

      let* () = Fs.copyPath(~src, ~dst);

      Fs.exists(dst);
    };

    Fs.withTempDir(f);
  };

  TestHarness.runRunAsyncTest(test);
};

let%test "copyPathLwt - copy nested file" = {
  let test = () => {
    let f = tempPath => {
      open RunAsync.Syntax;
      let nestedSrc = Path.(tempPath / "src_root" / "nested1");
      let nestedDest = Path.(tempPath / "dest_root" / "nested2");
      let src = Path.(nestedSrc / "src.txt");
      let dst = Path.(nestedDest / "dst.txt");
      let data = "test";
      let* () = Fs.createDir(nestedSrc);
      let* () = Fs.writeFile(~data, src);

      let* () = Fs.copyPath(~src, ~dst);

      Fs.exists(dst);
    };

    Fs.withTempDir(f);
  };

  TestHarness.runRunAsyncTest(test);
};

let%test "rmPathLwt - delete read only file" = {
  let test = () => {
    let f = tempPath => {
      open RunAsync.Syntax;
      let src = Path.(tempPath / "test.txt");
      let data = "test";
      let* () = Fs.writeFile(~data, src);

      /* Set file as read only, and verify we can still delete it */
      /* Tested on Windows, this sets the read-only flag there too */
      let () = Unix.chmod(Path.show(src), 0o444);

      let* () = Fs.rmPath(src);
      let* exists = Fs.exists(src);
      return(!exists);
    };

    Fs.withTempDir(f);
  };

  TestHarness.runRunAsyncTest(test);
};

let%test "rename - can rename a directory" = {
  let test = () => {
    let f = (srcTempPath, dstTempPath) => {
      open RunAsync.Syntax;
      let src = Path.(srcTempPath / "test.txt");
      let dst = dstTempPath;
      let data = "test";
      let* () = Fs.writeFile(~data, src);
      let src = srcTempPath;
      let* () = Fs.rename(~src, dst);
      return(true);
    };

    Fs.withTempDir(srcTempPath => {
      Fs.withTempDir(dstTempPath => {f(srcTempPath, dstTempPath)})
    });
  };

  TestHarness.runRunAsyncTest(test);
};
