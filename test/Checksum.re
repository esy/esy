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

let%test "checksum validates a simple file: sha1" = {
  let test = () => {
    let f = tempPath => {
      open RunAsync.Syntax;
      let path = Path.(tempPath / "checksum-test.txt");
      let data = "test checksum file";
      let* () = Fs.writeFile(~data, path);

      let expectedChecksum =
        EsyLib.Checksum.parse("sha1:7d85467b401b128e754b617621a7ed1f8f04724d");
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

let%test "checksum validates a simple file: sha256" = {
  let test = () => {
    let f = tempPath => {
      open RunAsync.Syntax;
      let path = Path.(tempPath / "checksum-test.txt");
      let data = "test checksum file";
      let* () = Fs.writeFile(~data, path);

      let expectedChecksum =
        EsyLib.Checksum.parse("sha256:d6f5b67d0ef090befcba899843e57a3aa19f8f0a6604fcea0baf808beefedace");
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

let%test "checksum validates a simple file: sha512" = {
  let test = () => {
    let f = tempPath => {
      open RunAsync.Syntax;
      let path = Path.(tempPath / "checksum-test.txt");
      let data = "test checksum file";
      let* () = Fs.writeFile(~data, path);

      let expectedChecksum =
        EsyLib.Checksum.parse("sha512:1e11fca838c4cf0fb843e326c8fb79912e15c665cf86feec31410d3cb1377f4fd5d75ec837b19a1029614260c2646c747fb8071133eec0e088b1376668a76666");
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
