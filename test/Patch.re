module Fs = EsyLib.Fs;
module Path = EsyLib.Path;
module RunAsync = EsyLib.RunAsync;

let%test "simple patch test" = {
  let test = () => {
    let f = tempPath => {
      open RunAsync.Syntax;
      let fileToPatch = Path.(tempPath / "input.txt");
      let patchFile = Path.(tempPath / "patch.txt");
      let originalContents = "Hello OCaml\n";

      /* Simple patch file to go from "Hello OCaml" -> "Hello Reason" */
      let patchContents = "--- input.txt\n+++ input.txt\n@@ -1 +1 @@\n-Hello OCaml\n+Hello Reason\n";
      let%bind () = Fs.createDir(tempPath);
      let%bind () = Fs.writeFile(~data=originalContents, fileToPatch);
      let%bind () = Fs.writeFile(~data=patchContents, patchFile);

      let%bind () =
        EsyLib.Patch.apply(~strip=0, ~root=tempPath, ~patch=patchFile, ());

      let%bind c = Fs.readFile(fileToPatch);
      return(c == "Hello Reason\n");
    };

    Fs.withTempDir(f);
  };

  TestHarness.runRunAsyncTest(test);
};
