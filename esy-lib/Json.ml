type t = Yojson.Safe.json

type 'a encoder = 'a -> t
type 'a decoder = t -> ('a, string) result

let to_yojson x = x
let of_yojson x = Ok x

let show = Yojson.Safe.pretty_to_string
let pp = Yojson.Safe.pretty_print

let compare a b =
  String.compare
    (Yojson.Safe.to_string a)
    (Yojson.Safe.to_string b)

let parse data =
  try Run.return (Yojson.Safe.from_string data)
  with Yojson.Json_error msg -> Run.errorf "error parsing JSON: %s" msg

let parseJsonWith parser json =
  Run.ofStringError (parser json)

let parseStringWith parser data =
  try
    let json = Yojson.Safe.from_string data in
    parseJsonWith parser json
  with Yojson.Json_error msg -> Run.errorf "error parsing JSON: %s" msg

let mergeAssoc items update =
  let toMap items =
    let f map (name, json) = StringMap.add name json map in
    List.fold_left ~f ~init:StringMap.empty items
  in
  let items = toMap items in
  let update = toMap update in
  let result = StringMap.mergeOverride items update in
  StringMap.bindings result

module Decode = struct

  let string (json : t) =
    match json with
    | `String v -> Ok v
    | _ -> Error "expected string"

  let nullable decode (json : t) =
    match json with
    | `Null -> Ok None
    | json ->
      begin match decode json with
      | Ok v -> Ok (Some v)
      | Error err -> Error err
      end

  let assoc (json : t) =
    match json with
    | `Assoc v -> Ok v
    | _ -> Error "expected object"

  let field ~name (json : t) =
    match json with
    | `Assoc items ->
      begin match List.find_opt ~f:(fun (k, _v) -> k = name) items with
      | Some (_, v) -> Ok v
      | None -> Error ("no such field: " ^ name)
      end
    | _ -> Error "expected object"

  let fieldOpt ~name (json : t) =
    match json with
    | `Assoc items ->
      begin match List.find_opt ~f:(fun (k, _v) -> k = name) items with
      | Some (_, v) -> Ok (Some v)
      | None -> Ok None
      end
    | _ -> Error "expected object"

  let fieldWith ~name parse json =
    match field ~name json with
    | Ok v -> parse v
    | Error err -> Error err

  let fieldOptWith ~name parse json =
    match fieldOpt ~name json with
    | Ok (Some v) ->
      begin match parse v with
      | Ok v -> Ok (Some v)
      | Error err -> Error err
      end
    | Ok None -> Ok None
    | Error err -> Error err

  let list ?(errorMsg="expected an array") value (json : t) =
    match json with
    | `List (items : t list) ->
      let f acc v = match acc, (value v) with
        | Ok acc, Ok v -> Ok (v::acc)
        | Ok _, Error err -> Error err
        | err, _ -> err
      in begin
      match List.fold_left ~f ~init:(Ok []) items with
      | Ok items -> Ok (List.rev items)
      | error -> error
      end
    | _ -> Error errorMsg

  let stringMap ?(errorMsg= "expected an object") value (json : t) =
    match json with
    | `Assoc items ->
      let f acc (k, v) = match acc, k, (value v) with
        | Ok acc, k, Ok v -> Ok (StringMap.add k v acc)
        | Ok _, _, Error err -> Error err
        | err, _, _ -> err
      in
      List.fold_left ~f ~init:(Ok StringMap.empty) items
    | _ -> Error errorMsg
end

module Encode = struct
  type field = (string * t) option

  let opt encode v =
    match v with
    | None -> `Null
    | Some v -> encode v

  let list encode v =
    `List (List.map ~f:encode v)

  let string v = `String v

  let assoc fields =
    let fields = List.filterNone fields in
    `Assoc fields

  let field name encode value =
    Some (name, encode value)

  let fieldOpt name encode value =
    match value with
    | None -> None
    | Some value -> Some (name, encode value)
end

module Print : sig
  val pp :
    ?ppListBox:(?indent:int -> t list Fmt.t -> t list Fmt.t)
    -> ?ppAssocBox:(?indent:int -> (string * t) list Fmt.t -> (string * t) list Fmt.t)
    -> t Fmt.t

  val ppRegular : t Fmt.t
end = struct
  let ppComma = Fmt.unit ",@ "

  (* from yojson *)
  let hex n =
    Char.chr (
      if n < 10 then n + 48
      else n + 87
    )

  (* from yojson *)
  let ppStringBody fmt s =
    for i = 0 to String.length s - 1 do
      match s.[i] with
          '"' -> Format.pp_print_string fmt "\\\""
        | '\\' -> Format.pp_print_string fmt "\\\\"
        | '\b' -> Format.pp_print_string fmt "\\b"
        | '\012' -> Format.pp_print_string fmt "\\f"
        | '\n' -> Format.pp_print_string fmt "\\n"
        | '\r' -> Format.pp_print_string fmt "\\r"
        | '\t' -> Format.pp_print_string fmt "\\t"
        | '\x00'..'\x1F'
        | '\x7F' as c ->
          Format.pp_print_string fmt "\\u00";
          Format.pp_print_char fmt (hex (Char.code c lsr 4));
          Format.pp_print_char fmt (hex (Char.code c land 0xf))
        | c ->
          Format.pp_print_char fmt c
    done

  let ppString =
    Fmt.quote ppStringBody

  let pp ?(ppListBox=Fmt.hvbox) ?(ppAssocBox=Fmt.hvbox) fmt json =
    let rec pp fmt json =
      Fmt.(vbox ppSyn) fmt json

    and ppSyn fmt json =
      match json with
      | `Bool v -> Fmt.bool fmt v
      | `Float v -> Fmt.float fmt v
      | `Int v -> Fmt.int fmt v
      | `Intlit v -> Fmt.string fmt v
      | `String v -> ppString fmt v
      | `Null -> Fmt.unit "null" fmt ()
      | `Variant (tag, args) ->
        begin match args with
        | None -> ppSyn fmt (`List [`String tag])
        | Some args -> ppSyn fmt (`List [`String tag; args])
        end
      | `Tuple items
      | `List items ->
        let pp fmt items =
          Format.fprintf
            fmt "[@;<0 0>%a@;<0 -2>]"
            (Fmt.list ~sep:ppComma ppListItem) items;
        in
        ppListBox ~indent:2 pp fmt items
      | `Assoc items ->
        let pp fmt items =
          Format.fprintf
            fmt "{@;<0 0>%a@;<0 -2>}"
            (Fmt.list ~sep:ppComma ppAssocItem) items
        in
        ppAssocBox ~indent:2 pp fmt items

    and ppListItem fmt item =
      Format.fprintf fmt "%a" pp item

    and ppAssocItem fmt (k, v) =
      match v with
      | `List items ->
        Format.fprintf
          fmt "@[<hv 2>%a: [@,%a@;<0 -2>]@]"
          ppString k (Fmt.list ~sep:ppComma ppListItem) items
      | `Assoc items ->
        Format.fprintf
          fmt "@[<hv 2>%a: {@,%a@;<0 -2>}@]"
          ppString  k (Fmt.list ~sep:ppComma ppAssocItem) items
      | _ ->
        Format.fprintf
          fmt "@[<h 0>%a:@ %a@]"
          ppString k pp v
    in

    pp fmt json

  let ppRegular = pp ~ppListBox:Fmt.vbox ~ppAssocBox:Fmt.vbox
end
