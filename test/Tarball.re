module EsyBash = EsyLib.EsyBash;
module Fs = EsyLib.Fs;
module Path = EsyLib.Path;
module RunAsync = EsyLib.RunAsync;
module Result = EsyLib.Result;

let%test "creates and unpacks a tarball" = {
  let test = () => {
    let f = tempPath => {
      open RunAsync.Syntax;
      let folderToCreate = Path.(tempPath / "test-folder");
      let* () = Fs.createDir(folderToCreate);
      let fileToCreate = Path.(folderToCreate / "test-file.txt");
      let data = "test data";
      let* () = Fs.writeFile(~data, fileToCreate);

      /* package up the file into a tarball */
      let filename = Path.(tempPath / "output.tar.gz");
      let* () = EsyLib.Tarball.create(~filename, folderToCreate);

      /* unpack the tarball */
      let dst = Path.(tempPath / "extract-folder");
      let* () = Fs.createDir(dst);
      let* () = EsyLib.Tarball.unpack(~dst, filename);

      let expectedOutputFile = Path.(dst / "test-file.txt");
      let* result = Fs.readFile(expectedOutputFile);
      return(result == data);
    };

    Fs.withTempDir(f);
  };

  TestHarness.runRunAsyncTest(test);
};

let%test "unpack tarball with stripcomponents" = {
  let test = () => {
    let f = tempPath => {
      open RunAsync.Syntax;
      let folderToCreate =
        Path.(
          tempPath / "test-folder" / "nested-folder-1" / "nested-folder-2"
        );
      let* () = Fs.createDir(folderToCreate);
      let fileToCreate = Path.(folderToCreate / "test-file.txt");
      let data = "test data";
      let* () = Fs.writeFile(~data, fileToCreate);

      /* package up the file into a tarball */
      let folderToPackage = Path.(tempPath / "test-folder");
      let filename = Path.(tempPath / "output.tar.gz");
      let* () = EsyLib.Tarball.create(~filename, folderToPackage);

      /* unpack the tarball */
      let dst = Path.(tempPath / "extract-folder");
      let* () = Fs.createDir(dst);
      let stripComponents = 2;
      let* () = EsyLib.Tarball.unpack(~stripComponents, ~dst, filename);

      let expectedOutputFile = Path.(dst / "test-file.txt");
      let* result = Fs.readFile(expectedOutputFile);
      return(result == data);
    };

    Fs.withTempDir(f);
  };

  TestHarness.runRunAsyncTest(test);
};

let%test "returns error if operation was not successfully" = {
  let test = () => {
    open RunAsync.Syntax;
    let dst = Path.(v("non-existent-path"));
    let fileName = Path.(v("non-existent-file.tgz"));
    let%lwt result = EsyLib.Tarball.unpack(~dst, fileName);
    switch (result) {
    | Ok(_) => return(false)
    | Error(_) => return(true)
    };
  };

  TestHarness.runRunAsyncTest(test);
};
