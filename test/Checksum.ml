module Fs = EsyLib.Fs
module Path = EsyLib.Path

let%test "checksum validates a simple file: md5" =
    let test () = 
        let f tempPath =
            let path = Path.(tempPath / "checksum-test.txt") in
            let data = "test checksum file" in
            let%lwt _ = Fs.writeFile ~data path in

            let expectedChecksum = EsyLib.Checksum.parse "md5:97d37ce810cfcff2665f45e9da4449b7" in
            match expectedChecksum with
            | Error _ -> Lwt.return false
            | Ok v -> 
                let%lwt actualChecksum = EsyLib.Checksum.checkFile ~path v in
                match actualChecksum with
                | Ok _ -> Lwt.return true
                | _ -> Lwt.return false
        in
        Fs.withTempDir f
    in
    TestLwt.runLwtTest test
