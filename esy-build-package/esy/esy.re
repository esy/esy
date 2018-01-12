let main = () => {
  let%lwt sandbox = EsyCore.Sandbox.ofDir(EsyCore.Path.v("."));
  switch sandbox {
  | Ok(sandbox) => print_endline(EsyCore.Package.show(sandbox))
  | Error(msg) => print_endline(msg)
  };
  Lwt.return();
};

Lwt_main.run(main());
