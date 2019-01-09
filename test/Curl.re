include EsyLib.Curl;

module EsyBash = EsyLib.EsyBash;
module Fs = EsyLib.Fs;
module Path = EsyLib.Path;
module RunAsync = EsyLib.RunAsync;
module Result = EsyLib.Result;

let%test "curl download simple file" = {
  let test = () => {
    let f = tempPath => {
      open RunAsync.Syntax;
      let fileToCurl = Path.(tempPath / "input.txt");
      let data = "test";
      let%bind () = Fs.createDir(tempPath);
      let%bind () = Fs.writeFile(~data, fileToCurl);

      /* use curl to copy the file, as opposed to hitting an external server */
      let output = Path.(tempPath / "output.txt");

      /* We need to normalize the path on Windows - file:///E:/.../ won't work! */
      /* The normalize gives us a path of the form file:///cygdrive/e/.../ which does. */
      /* This won't impact HTTP requests though - just our test using the local file system */
      let url = EsyBash.normalizePathForCygwin(Path.show(fileToCurl));

      let%bind () = EsyLib.Curl.download(~output, "file://" ++ url);

      /* validate we were able to download it */
      Fs.exists(output);
    };

    Fs.withTempDir(f);
  };

  TestHarness.runRunAsyncTest(test);
};

let%test "curl gives error when failing to download" = {
  let test = () => {
    let f = tempPath => {
      open RunAsync.Syntax;
      let output = Path.(tempPath / "output.txt");
      let url = "file:///some/nonexistent/file";
      let%lwt result = EsyLib.Curl.download(~output, url);
      switch (result) {
      | Error(_) => return(true)
      | _ => return(false)
      };
    };

    Fs.withTempDir(f);
  };

  TestHarness.runRunAsyncTest(test);
};

let%test "curl gives error when failing to download from localhost" = {
  let test = () => {
    let f = tempPath => {
      open RunAsync.Syntax;
      let output = Path.(tempPath / "output.txt");
      let url = "http://localhost:5251/b/-/b-0-4-5-1.tgz";
      let%lwt result = EsyLib.Curl.download(~output, url);
      switch (result) {
      | Error(_) => return(true)
      | _ => return(false)
      };
    };

    Fs.withTempDir(f);
  };

  TestHarness.runRunAsyncTest(test);
};
