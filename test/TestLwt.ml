(* Helper to run a test that needs Lwt promises *)
let runLwtTest f = 
    let p: bool Lwt.t =
        let%lwt ret = f () in
        Lwt.return ret
    in
    Lwt_main.run p

