include EsyLib.Curl

module Fs = EsyLib.Fs
module Path = EsyLib.Path
module System = EsyLib.System

let%test "copyPathLwt - copy simple file" =
    let test () =
        let f tempPath =
            let src = Path.(tempPath / "src.txt") in
            let dst = Path.(tempPath / "dst.txt") in
            let data = "test" in
            let%lwt _ = Fs.createDir tempPath in
            let%lwt _ = Fs.writeFile ~data src in

            let%lwt _ = Fs.copyPath ~src ~dst in

            let%lwt exists = Fs.exists dst in
            match exists with
            | Ok v -> Lwt.return v
            | _ -> Lwt.return false
        in
        Fs.withTempDir f
    in
    TestLwt.runLwtTest test

let%test "copyPathLwt - copy nested file" =
    let test () =
        let f tempPath =
            let nestedSrc = Path.(tempPath / "src_root" / "nested1") in
            let nestedDest = Path.(tempPath / "dest_root" / "nested2") in
            let src = Path.(nestedSrc / "src.txt") in
            let dst = Path.(nestedDest / "dst.txt") in
            let data = "test" in
            let%lwt _ = Fs.createDir nestedSrc in
            let%lwt _ = Fs.writeFile ~data src in

            let%lwt _ = Fs.copyPath ~src ~dst in

            let%lwt exists = Fs.exists dst in
            match exists with
            | Ok v -> Lwt.return v
            | _ -> Lwt.return false
        in
        Fs.withTempDir f
    in
    TestLwt.runLwtTest test

let%test "rmPathLwt - delete read only file" =
    let test () =
        let f tempPath =
            let src = Path.(tempPath / "test.txt") in
            let data = "test" in
            let%lwt _ = Fs.writeFile ~data src in

            (* Set file as read only, and verify we can still delete it *)
            let%lwt _ = match System.Platform.host with
            | System.Platform.Windows -> 
                let ic = Unix.open_process_in ("attrib +r " ^ (Path.show src)) in
                let _ = input_line ic in
                Lwt.return (close_in ic)
            | _ -> 
                let _ = Fs.chmod 000 src in
                Lwt.return ()
            in

            let%lwt _ = Fs.rmPath src in
            let%lwt exists = Fs.exists src in
            match exists with
            | Ok _ -> Lwt.return true
            | _ -> Lwt.return false
        in
        Fs.withTempDir f
    in
    TestLwt.runLwtTest test
