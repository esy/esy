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

let%test "stat test" =
    let f () =
        let%lwt result = Fs.stat (Path.v "C:/test") in
        match result with 
        | Ok _ -> Lwt.return true
        | _ -> Lwt.return false
    in
    testLwt f

let%test "curl simple file" =
    let f () = 
        let tempPath = Path.v "C:/test1091i50" in
        let%lwt _ = Fs.createDir tempPath in
        let%lwt result = Fs.exists (tempPath) in
        match result with
        | Ok true -> Lwt.return true
        | _ -> Lwt.return false
    in
    testLwt f
