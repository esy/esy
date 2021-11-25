module Fs = EsyLib.Fs;
module Path = EsyLib.Path;
module RunAsync = EsyLib.RunAsync;

let%test "checksum validates a simple file: md5" = {
  let test = () => {
    let f = tempPath => {
      open RunAsync.Syntax;
      let path = Path.(tempPath / "checksum-test.txt");
      let data = "test checksum file";
      let* () = Fs.writeFile(~data, path);

      let expectedChecksum =
        EsyLib.Checksum.parse("md5:97d37ce810cfcff2665f45e9da4449b7");
      switch (expectedChecksum) {
      | Error(_) => return(false)
      | Ok(v) =>
        let* _actualChecksum = EsyLib.Checksum.checkFile(~path, v);
        return(true);
      };
    };

    Fs.withTempDir(f);
  };

  TestHarness.runRunAsyncTest(test);
};
