let pathConv =
  let open Cmdliner in
  let parse = Path.of_string in
  let print = Path.pp in
  Arg.conv ~docv:"PATH" (parse, print)
