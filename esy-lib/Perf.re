let measure = (~label, f) => {
  let before = Unix.gettimeofday();
  let res = f();
  let after = Unix.gettimeofday();
  let () = {
    let spent = 1000.0 *. (after -. before);
    Esy_logs.info(m => m(~header="time", "%s: %fms", label, spent));
  };

  res;
};

let measureLwt = (~label, f) => {
  let before = Unix.gettimeofday();
  let%lwt res = f();
  let after = Unix.gettimeofday();
  let%lwt () = {
    let spent = 1000.0 *. (after -. before);
    Esy_logs_lwt.debug(m => m(~header="time", "%s: %fms", label, spent));
  };

  Lwt.return(res);
};
