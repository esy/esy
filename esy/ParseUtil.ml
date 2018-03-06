let formatParseError ?src ~cnum msg =
  match src with
  | None -> msg
  | Some src ->
    let src = (String.sub src 0 (cnum + 5)) ^ "..." in
    let line =
      String.init
        (String.length src)
        (fun i -> if i = cnum then '^' else ' ')
    in
    Printf.sprintf "%s:\n>\n> %s\n> %s" msg src line

