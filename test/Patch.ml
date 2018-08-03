module EsyBash = EsyLib.EsyBash
module Fs = EsyLib.Fs
module Path = EsyLib.Path
module RunAsync = EsyLib.RunAsync
module Result = EsyLib.Result

let%test "simple patch test" =
    let test () = 
        let f tempPath =
            let fileToPatch = Path.(tempPath / "input.txt") in
            let patchFile = Path.(tempPath / "path.txt") in
            let originalContents = "Hello OCaml" in
            let patchContents = "--- ./input.txt\n+++ ./input.txt\n@@ -1,1 +1,1 @@\n- Hello OCaml\n+Hello Reason\n" in
            let%lwt _ = Fs.createDir tempPath in
            let%lwt _ = Fs.writeFile ~data:originalContents fileToPatch in
            let%lwt _ = Fs.writeFile ~data:patchContents patchFile in

            let%lwt result = Patch.apply ~strip:0 ~directory:tempPath ~patch:patchFile in
            match result with
            | Ok _ -> Lwt.return true
            | Error _ -> Lwt.return false
        in
        Fs.withTempDir f
    in
    TestLwt.runLwtTest test
