module EsyBash = EsyLib.EsyBash
module Fs = EsyLib.Fs
module Path = EsyLib.Path
module RunAsync = EsyLib.RunAsync
module Result = EsyLib.Result

let%test "creates and unpacks a tarball" =
    let test () = 
        let f tempPath =
            let folderToCreate = Path.(tempPath / "test-folder") in
            let%lwt _ = Fs.createDir folderToCreate in
            let fileToCreate = Path.(folderToCreate / "test-file.txt") in
            let data = "test data" in
            let%lwt _ = Fs.writeFile ~data fileToCreate in

            (* package up the file into a tarball *)
            let filename = Path.(tempPath / "output.tar.gz") in
            let%lwt _ = EsyLib.Tarball.create ~filename folderToCreate in

            (* unpack the tarball *)
            let dst = Path.(tempPath / "extract-folder") in
            let%lwt _ = Fs.createDir dst in 
            let%lwt _ = EsyLib.Tarball.unpack ~dst filename in

            let expectedOutputFile = Path.(dst / "test-file.txt") in
            let%lwt result = Fs.readFile expectedOutputFile in
            match result with 
            | Ok v -> Lwt.return (v = data)
            | _ -> Lwt.return false
        in
        Fs.withTempDir f
    in
    TestLwt.runLwtTest test
