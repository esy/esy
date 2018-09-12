include Angstrom

module Let_syntax = struct
  let map ~f p = p >>| f
  let bind ~f p = p >>= f
end

let ignore p =
  p >>| (fun _ -> ())

let maybe p = option None (p >>| fun v -> Some v)

let till c p =
  let%bind input = take_while1 c in
  match parse_string p input with
  | Ok fname -> return fname
  | Error msg -> fail msg

let pair =
  let pair x y = x, y in
  fun a b -> lift2 pair a b

let hex =
  take_while1 (function
    | '0'..'9' -> true
    | 'a' | 'b' | 'c' | 'd' | 'e' | 'f' -> true
    | _ -> false
  ) <?> "hex"

let parse p input =
  parse_string (p <* end_of_input) input

module Test = struct
  let expectParses ~pp ~equal parse input expectation =
    match parse input with
    | Error err ->
      Format.printf "Error parsing '%s': %s@\n" input err;
      false
    | Ok v when equal v expectation -> true
    | Ok v ->
      Format.printf
      "Error parsing '%s':@\n  expected: %a@\n  got:      %a@\n"
        input pp expectation pp v;
      false
end
