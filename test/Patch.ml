module Fs = EsyLib.Fs
module Path = EsyLib.Path
module RunAsync = EsyLib.RunAsync

let%test "simple patch test" =
    let test () =
        let f tempPath =
            let open RunAsync.Syntax in
            let fileToPatch = Path.(tempPath / "input.txt") in
            let patchFile = Path.(tempPath / "patch.txt") in
            let originalContents = "Hello OCaml\n" in

            (* Simple patch file to go from "Hello OCaml" -> "Hello Reason" *)
            let patchContents = "--- input.txt\n+++ input.txt\n@@ -1 +1 @@\n-Hello OCaml\n+Hello Reason\n" in
            let%bind () = Fs.createDir tempPath in
            let%bind () = Fs.writeFile ~data:originalContents fileToPatch in
            let%bind () = Fs.writeFile ~data:patchContents patchFile in

            let%bind () = EsyLib.Patch.apply ~strip:0 ~root:tempPath ~patch:patchFile () in

            let%bind c = Fs.readFile fileToPatch in
            return (c = "Hello Reason\n")
        in
        Fs.withTempDir f
    in
    TestHarness.runRunAsyncTest test
