let fail msg = failwith msg

let failf fmt =
  let kerr _ = failwith (Format.flush_str_formatter ()) in
  Format.kfprintf kerr Format.str_formatter fmt
