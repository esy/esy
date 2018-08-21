include EsyLib.Curl

module EsyBash = EsyLib.EsyBash
module Fs = EsyLib.Fs
module Path = EsyLib.Path
module RunAsync = EsyLib.RunAsync
module Result = EsyLib.Result

let%test "copyPathLwt - copy simple file" =
    let test () = 
        let f tempPath =
            let src = Path.(tempPath / "src.txt") in
            let dst = Path.(tempPath / "dst.txt") in
            let data = "test" in
            let%lwt _ = Fs.createDir tempPath in
            let%lwt _ = Fs.writeFile ~data src in

            (* use curl to copy the file, as opposed to hitting an external server *)
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
            print_endline("temppath: " ^ Path.toString tempPath);
            let src = Path.(nestedSrc / "src.txt") in
            let dst = Path.(nestedDest / "dst.txt") in
            let data = "test" in
            let%lwt _ = Fs.createDir nestedSrc in
            let%lwt _ = Fs.writeFile ~data src in

            (* use curl to copy the file, as opposed to hitting an external server *)
            let%lwt _ = Fs.copyPath ~src ~dst in
            let%lwt exists = Fs.exists dst in
            match exists with
            | Ok v -> Lwt.return v
            | _ -> Lwt.return false
        in
        Fs.withTempDir f
    in
    TestLwt.runLwtTest test
