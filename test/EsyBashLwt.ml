module Cmd = EsyLib.Cmd
module Fs = EsyLib.Fs
module Path = EsyLib.Path

module EsyBashLwt = EsyLib.EsyBashLwt
module RunAsync = EsyLib.RunAsync

let%test "execute a simple bash command (cross-platform)" =
    let t () =
        let f p =
            let%lwt stdout =
              Lwt.finalize
                (fun () -> Lwt_io.read p#stdout)
                (fun () -> Lwt_io.close p#stdout)
            in
            RunAsync.return (String.trim stdout = "hello-world")
        in
        let cmd = Cmd.(
            v "bash"
            % "-c"
            % "echo hello-world"
        ) in
        EsyBashLwt.with_process_full cmd f
    in
    TestHarness.runRunAsyncTest t
