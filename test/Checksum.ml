module Fs = EsyLib.Fs
module Path = EsyLib.Path
module RunAsync = EsyLib.RunAsync

let%test "checksum validates a simple file: md5" =
    let test () =
        let f tempPath =
            let open RunAsync.Syntax in
            let path = Path.(tempPath / "checksum-test.txt") in
            let data = "test checksum file" in
            let%bind () = Fs.writeFile ~data path in

            let expectedChecksum = EsyLib.Checksum.parse "md5:97d37ce810cfcff2665f45e9da4449b7" in
            match expectedChecksum with
            | Error _ -> return false
            | Ok v ->
                let%bind _actualChecksum = EsyLib.Checksum.checkFile ~path v in
                return true
        in
        Fs.withTempDir f
    in
    TestHarness.runRunAsyncTest test
