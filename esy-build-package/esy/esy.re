let main = () => {
  let%lwt sandbox = EsyCore.Sandbox.ofDir(EsyCore.Path.v("."));
  switch sandbox {
  | Ok(sandbox) => EsyCore.BuildTask.ofPackage(sandbox)
  | Error(msg) => print_endline(msg)
  };
  Lwt.return();
};

Lwt_main.run(main());
