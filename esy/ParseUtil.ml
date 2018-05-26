let formatParseError ?src ~cnum msg =
  match src with
  | None -> msg
  | Some src ->
    let ctx =
      let cnum = min (String.length src) (cnum + 5) in
      (String.sub src 0 cnum) ^ "..."
    in
    let line =
      String.init
        (String.length ctx)
        (fun i -> if i = cnum then '^' else ' ')
    in
    Printf.sprintf "%s:\n>\n> %s\n> %s" msg ctx line

