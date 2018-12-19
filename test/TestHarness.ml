let runRunAsyncTest f =
    let p =
        let%lwt ret = f () in
        Lwt.return ret
    in
    match Lwt_main.run p with
    | Ok v -> v
    | Error err ->
      Format.eprintf "ERROR: %a@." EsyLib.Run.ppError err;
      false
