let main = () => {
  module Let_syntax = EsyLib.Result.Let_syntax;
  let%lwt sandbox = EsyCore.Sandbox.ofDir(EsyCore.Path.v("."));
  switch sandbox {
  | Ok(sandbox) =>
    let _ = EsyCore.BuildTask.ofPackage(sandbox);
    ();
  | Error(msg) => print_endline(msg)
  };
  Lwt.return();
};

Lwt_main.run(main());
