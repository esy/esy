[@@@ocaml.warning "-32"]
type alpha =
  A of string * num option
and num =
  N of int * alpha option
  [@@deriving (eq, show)]

type t =
  alpha
  [@@deriving (eq, show)]

let toString v =
  let rec aToString = function
    | A (s, None) -> s
    | A (s, Some v) -> s ^ nToString v
  and nToString = function
    | N (s, None) -> string_of_int s
    | N (s, Some v) -> string_of_int s ^ aToString v
  in aToString v

let prerelease _ = false
let stripPrerelease v = v

let%test_module "toString" = (module struct

  let%test "<empty>" = toString (A ("", None)) = ""
  let%test "1" = toString (A ("", Some (N (1, None)))) = "1"
  let%test "v1" = toString (A ("v", Some (N (1, None)))) = "v1"
  let%test "1.2" = toString
    (A ("", Some (N (1, Some (A (".", Some (N (2, None)))))))) = "1.2"

end)

let parse text =

  let rec getNums text pos =
    if pos < String.length text
    then
      match text.[pos] with
      | '0'..'9' -> getNums text (pos + 1)
      | _ -> pos
    else pos
  in

  let rec getNonNums text pos =
    if pos < String.length text
    then
      match text.[pos] with
      | '0'..'9' -> pos
      | _ -> getNonNums text (pos + 1)
    else
      pos
  in

  let len = String.length text in

  let rec getNum pos =
    if pos >= len
    then None
    else
      let tpos = getNums text pos in
      let num = String.sub text pos (tpos - pos) in
      Some (N (int_of_string num, getString tpos))

  and getString pos =
    if pos >= len
    then None
    else
      match text.[pos] with
      | '0'..'9' -> Some (A ("", getNum pos))
      | _ ->
        let tpos = getNonNums text pos in
        let t = String.sub text pos (tpos - pos) in
        Some (A (t, getNum tpos))
  in
  match getString 0 with
  | None -> Ok (A ("", None))
  | Some a -> Ok a

let parseExn v =
  match parse v with
  | Ok v -> v
  | Error err -> raise (Invalid_argument err)

let%test_module "parse" = (module struct

  let expectParse v expectation =
    match parse v with
    | Error err ->
      print_endline ("Parse Error: " ^ err);
      false
    | Ok res ->
      if res = expectation
      then true
      else (
        print_endline ("Expected: " ^ show expectation);
        print_endline ("Got     : " ^ show res);
        false
      )

  let%test "<empty>" = expectParse
    ""
    (A ("", None))

  let%test "1" = expectParse
    "1"
    (A ("", Some (N (1, None))))

  let%test "1.2" = expectParse
    "1.2"
    (A ("", Some (N (1, Some (A (".", Some (N (2, None))))))))

  let%test "v1" = expectParse
    "v1"
    (A ("v", Some (N (1, None))))

  let%test "1a" = expectParse
    "1a"
    (A ("", Some (N (1, Some (A ("a", None))))))

  let%test "~" = expectParse
    "~"
    (A ("~", None))

  let%test "~beta" = expectParse
    "~beta"
    (A ("~beta", None))

  let%test "1~beta" = expectParse
    "1~beta"
    (A ("", Some (N (1, Some (A ("~beta", None))))))

  let%test "4.02+7" = expectParse
    "4.02+7"
    (A ("", Some (N (4, Some (A (".", Some (N (2, Some (A ("+", Some (N (7, None))))))))))))

  let%test "~~" = expectParse
    "~~"
    (A ("~~", None))

end)

let compare a b =
  let module String = Astring.String in
  let intCompare a b = if a > b then 1 else if a < b then -1 else 0 in

  let isWeakSuffix suffix =
    not (String.is_empty suffix) && String.get suffix 0 = '~'
  in

  let rec compareA = function
    | Some (A (a, na)), Some (A (b, nb)) ->
      begin match isWeakSuffix a, isWeakSuffix b with
      | true, false -> -1
      | false, true -> 1
      | true, true | false, false ->
        let r = String.compare a b in
        if r = 0 then compareN (na, nb) else r
      end
    | Some (A (a, _)), None when isWeakSuffix a -> -1
    | Some _, None -> 1
    | None, Some (A (b, _)) when isWeakSuffix b -> 1
    | None, Some _ -> -1
    | None, None -> 0

  and compareN = function
    | Some (N (a, na)), Some (N (b, nb)) ->
      let r = intCompare a b in
      if r = 0 then compareA (na, nb) else r
    | Some _, None -> 1
    | None, Some _ -> -1
    | None, None -> 0
  in
  compareA (Some a, Some b)

let%test_module "compare" = (module struct
  let v = parseExn

  let%test "1 = 1" =
    compare (v "1") (v "1") = 0

  let%test "2 > 1" =
    compare (v "2") (v "1") = 1

  let%test "1 < 2" =
    compare (v "1") (v "2") = -1

  let%test "4.4.2000 < 4.6.1" =
    compare (v "4.4.2000") (v "4.6.1") = -1

  (* This is non-intuitive but true, see JaneStreet libs on opam *)
  let%test "v0.9.0 > 113.0.0" =
    compare (v "v0.9.0") (v "113.0.0") = 1

  (* Test a special case with ~ *)
  let%test "1.0.0 > 1.0.0~beta" =
    compare (v "1.0.0") (v "1.0.0~beta") = 1
  let%test "1.0.0~beta < 1.0.0~beta" =
    compare (v "1.0.0~beta") (v "1.0.0") = -1
  let%test "1.0.0~beta1 < 1.0.0~beta2" =
    compare (v "1.0.0~beta1") (v "1.0.0~beta2") = -1
  let%test "1.0.0~alpha < 1.0.0~beta" =
    compare (v "1.0.0~alpha") (v "1.0.0~beta") = -1
  let%test "1.0.0~beta19 < 1.0.0~beta.19.1" =
    compare (v "1.0.0~beta19") (v "1.0.0~beta19.1") = -1

end)

module AsSemver = struct

  let stripCommonPrefix = function
    | A ("", Some n) -> Some n
    | A ("v", Some n) -> Some n
    | _ -> None

  let major v =
    let open Option.Syntax in
    match%bind stripCommonPrefix v with
    | N (major, None) -> Some major
    | N (major, Some (A (".", Some (N (_, None))))) -> Some major
    | N (major, Some (A (".", Some (N (_, Some (A (".", Some (N (_, _))))))))) -> Some major
    | _ -> None

  let minor v =
    let open Option.Syntax in
    match%bind stripCommonPrefix v with
    | N (_major, None) -> Some 0
    | N (_major, Some (A (".", Some (N (minor, None))))) -> Some minor
    | N (_major, Some (A (".", Some (N (minor, Some (A (".", Some (N (_, _))))))))) -> Some minor
    | _ -> None

  let patch v =
    let open Option.Syntax in
    match%bind stripCommonPrefix v with
    | N (_major, None) -> return 0
    | N (_major, Some (A (".", Some (N (_minor, None))))) -> return 0
    | N (_major, Some (A (".", Some (N (_minor, Some (A (".", Some (N (patch, _))))))))) -> return patch
    | _ -> None

  let nextPatch =
    let open Option.Syntax in
    function
    | A (_prefix, None) -> None
    | A (prefix, Some n) ->
      let%bind n = match n with
      | N (major, None) ->
        return (N (major, Some (A (".", Some (N (0, Some (A (".", Some (N (1, None))))))))))
      | N (major, Some (A (".", Some (N (minor, None))))) ->
        return (N (major, Some (A (".", Some (N (minor, Some (A (".", Some (N (1, None))))))))))
      | N (major, Some (A (".", Some (N (minor, Some (A (".", Some (N (patch, suffix))))))))) ->
        return (N (major, Some (A (".", Some (N (minor, Some (A (".", Some (N (patch + 1, suffix))))))))))
      | _ -> None
      in return (A (prefix, Some n))

  let nextMinor =
    let open Option.Syntax in
    function
    | A (_prefix, None) -> None
    | A (prefix, Some n) ->
      let%bind n = match n with
      | N (major, None) ->
        return (N (major, Some (A (".", Some (N (1, None))))))
      | N (major, Some (A (".", Some (N (minor, suffix))))) ->
        return (N (major, Some (A (".", Some (N (minor + 1, suffix))))))
      | _ -> None
      in return (A (prefix, Some n))

end

let to_yojson v = `String (toString v)
let of_yojson = function
  | `String v -> parse v
  | _ -> Error "expected string"
