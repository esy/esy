let runRunAsyncTest = f => {
  let p = {
    let%lwt ret = f();
    Lwt.return(ret);
  };

  switch (Lwt_main.run(p)) {
  | Ok(v) => v
  | Error(err) =>
    Format.eprintf("ERROR: %a@.", EsyLib.Run.ppError, err);
    false;
  };
};
