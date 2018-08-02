include EsyLib.Checksum

module Fs = EsyLib.Fs
module Path = EsyLib.Path

let%test "checksum validates a simple file" =
    let test () = 
        let f tempPath =
            let path = Path.(tempPath / "checksum-test.txt") in
            let data = "test checksum file" in
            let%lwt _ = Fs.writeFile ~data path in

            let expectedChecksum = Checksum.parse "md5:test" in
            let actualChecksum = Checksum.checkFile ~path expectedChecksum in
            match actualChecksum with
            | Ok -> Lwt.return true
            | _ -> Lwt.return false
        in
        Fs.withTempDir f
    in
    TestLwt.runLwtTest test
