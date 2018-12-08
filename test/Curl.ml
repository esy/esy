include EsyLib.Curl

module EsyBash = EsyLib.EsyBash
module Fs = EsyLib.Fs
module Path = EsyLib.Path
module RunAsync = EsyLib.RunAsync
module Result = EsyLib.Result

let%test "curl download simple file" =
    let test () = 
        let f tempPath =
            let fileToCurl = Path.(tempPath / "input.txt") in
            let data = "test" in
            let%lwt _ = Fs.createDir tempPath in
            let%lwt _ = Fs.writeFile ~data fileToCurl in

            (* use curl to copy the file, as opposed to hitting an external server *)
            let output = Path.(tempPath / "output.txt") in

            (* We need to normalize the path on Windows - file:///E:/.../ won't work! *)
            (* The normalize gives us a path of the form file:///cygdrive/e/.../ which does. *)
            (* This won't impact HTTP requests though - just our test using the local file system *)
            let url = EsyBash.normalizePathForCygwin (Path.show(fileToCurl)) in

            let%lwt _: unit EsyLib.Run.t = EsyLib.Curl.download ~output ("file://" ^ url) in

            (* validate we were able to download it *) 
            let%lwt result = Fs.exists (output) in
            match result with
            | Ok true -> Lwt.return true
            | _ -> Lwt.return false
        in
        Fs.withTempDir f
    in
    TestLwt.runLwtTest test

let%test "curl gives error when failing to download" =
    let test () = 
        let f tempPath =
            let output = Path.(tempPath / "output.txt") in
            let url = "file:///some/nonexistent/file" in
            let%lwt result = EsyLib.Curl.download ~output url in
            match result with
            | Error _ -> Lwt.return true
            | _ -> Lwt.return false
        in
        Fs.withTempDir f
    in
    TestLwt.runLwtTest test

let%test "curl gives error when failing to download from localhost" =
    let test () =
        let f tempPath =
            let output = Path.(tempPath / "output.txt") in
            let url = "http://localhost:5251/b/-/b-0-4-5-1.tgz" in
            let%lwt result = EsyLib.Curl.download ~output url in
            match result with
            | Error _ -> Lwt.return true
            | _ -> Lwt.return false
        in
        Fs.withTempDir f
    in
    TestLwt.runLwtTest test
