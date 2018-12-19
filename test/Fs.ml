include EsyLib.Curl

module RunAsync = EsyLib.RunAsync
module Fs = EsyLib.Fs
module Path = EsyLib.Path
module System = EsyLib.System

let%test "copyPathLwt - copy simple file" =
    let test () =
        let f tempPath =
            let open RunAsync.Syntax in
            let src = Path.(tempPath / "src.txt") in
            let dst = Path.(tempPath / "dst.txt") in
            let data = "test" in
            let%bind () = Fs.createDir tempPath in
            let%bind () = Fs.writeFile ~data src in

            let%bind () = Fs.copyPath ~src ~dst in

            Fs.exists dst
        in
        Fs.withTempDir f
    in
    TestHarness.runRunAsyncTest test

let%test "copyPathLwt - copy nested file" =
    let test () =
        let f tempPath =
            let open RunAsync.Syntax in
            let nestedSrc = Path.(tempPath / "src_root" / "nested1") in
            let nestedDest = Path.(tempPath / "dest_root" / "nested2") in
            let src = Path.(nestedSrc / "src.txt") in
            let dst = Path.(nestedDest / "dst.txt") in
            let data = "test" in
            let%bind () = Fs.createDir nestedSrc in
            let%bind () = Fs.writeFile ~data src in

            let%bind () = Fs.copyPath ~src ~dst in

            Fs.exists dst
        in
        Fs.withTempDir f
    in
    TestHarness.runRunAsyncTest test

let%test "rmPathLwt - delete read only file" =
    let test () =
        let f tempPath =
            let open RunAsync.Syntax in
            let src = Path.(tempPath / "test.txt") in
            let data = "test" in
            let%bind () = Fs.writeFile ~data src in

            (* Set file as read only, and verify we can still delete it *)
            (* Tested on Windows, this sets the read-only flag there too *)
            let () = Unix.chmod (Path.show src) 0o444 in

            let%bind () = Fs.rmPath src in
            let%bind exists = Fs.exists src in
            return (not exists)
        in
        Fs.withTempDir f
    in
    TestHarness.runRunAsyncTest test
