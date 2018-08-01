include EsyLib.Curl

module Fs = EsyLib.Fs
module Path = EsyLib.Path
module RunAsync = EsyLib.RunAsync

let testLwt f = 
    let p: bool Lwt.t =
        let%lwt ret = f () in
        Lwt.return ret
    in
    Lwt_main.run p

let%test "curl download simple file" =
    (*https://stackoverflow.com/questions/21023048/copying-local-files-with-curl*)
    let test () = 
        let f tempPath =
            let fileToCurl = Path.(tempPath / "input.txt") in
            let data = "test" in
            let%lwt _ = Fs.createDir tempPath in
            let%lwt _ = Fs.writeFile ~data fileToCurl in

            (* use curl to copy the file *)
            let output = Path.(tempPath / "output.txt") in
            let url = "file:///" ^ Path.to_string(fileToCurl) in
            let%lwt _ = EsyLib.Curl.download ~output url in

            (* validate we were able to download it *) 
            let%lwt result = Fs.exists (output) in
            match result with
            | Ok true -> Lwt.return true
            | _ -> Lwt.return false
        in
        Fs.withTempDir f
    in
    testLwt test
