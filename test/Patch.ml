module Fs = EsyLib.Fs
module Path = EsyLib.Path

let%test "simple patch test" =
    let test () = 
        let f tempPath =
            print_endline ("Running test: " ^ (Path.to_string tempPath));
            let fileToPatch = Path.(tempPath / "input.txt") in
            let patchFile = Path.(tempPath / "patch.txt") in
            let originalContents = "Hello OCaml\n" in

            (* Simple patch file to go from "Hello OCaml" -> "Hello Reason" *)
            let patchContents = "--- input.txt\n+++ input.txt\n@@ -1 +1 @@\n-Hello OCaml\n+Hello Reason\n" in
            let%lwt _ = Fs.createDir tempPath in
            let%lwt _ = Fs.writeFile ~data:originalContents fileToPatch in
            let%lwt _ = Fs.writeFile ~data:patchContents patchFile in

            let%lwt _ = EsyLib.Patch.apply ~strip:0 ~root:tempPath ~patch:patchFile () in

            match%lwt Fs.readFile fileToPatch with
            | Ok c -> Lwt.return (c = "Hello Reason\n")
            | _ -> Lwt.return false
        in
        Fs.withTempDir f
    in
    TestLwt.runLwtTest test
