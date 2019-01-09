module Cmd = EsyLib.Cmd;
module Fs = EsyLib.Fs;
module Path = EsyLib.Path;

module EsyBashLwt = EsyLib.EsyBashLwt;
module RunAsync = EsyLib.RunAsync;

let%test "execute a simple bash command (cross-platform)" = {
  let t = () => {
    let f = p => {
      let%lwt stdout =
        Lwt.finalize(
          () => Lwt_io.read(p#stdout),
          () => Lwt_io.close(p#stdout),
        );

      RunAsync.return(String.trim(stdout) == "hello-world");
    };

    let cmd = Cmd.(v("bash") % "-c" % "echo hello-world");
    EsyBashLwt.with_process_full(cmd, f);
  };

  TestHarness.runRunAsyncTest(t);
};
