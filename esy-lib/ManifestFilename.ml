type t =
  | Esy of string
  | Opam of string
  [@@deriving (eq, ord)]

let hasExtension ext =
  let re =
    let open Re in
    compile (seq [bos; rep1 any; str ext; eos])
  in
  Re.execp re

let parse fname =
  let open Result.Syntax in
  if fname = "opam"
  then return (Opam fname)
  else if hasExtension ".opam" fname
  then return (Opam fname)
  else if hasExtension ".json" fname
  then return (Esy fname)
  else errorf "invalid manifest filename: %s" fname

let parseExn fname =
  match parse fname with
  | Ok fname -> fname
  | Error msg -> raise (Invalid_argument msg)

let parser =
  let make fname =
    match parse fname with
    | Ok v -> Parse.return v
    | Error msg -> Parse.fail msg
  in
  Parse.(take_while1 (fun _ -> true) >>= make)

let to_yojson fname =
  match fname with
  | Esy fname -> `String fname
  | Opam fname -> `String fname

let of_yojson json =
  let open Result.Syntax in
  match json with
  | `String fname -> parse fname
  | _ -> error "expected string"

let toString fname =
  match fname with
  | Esy fname -> fname
  | Opam fname -> fname

let show = toString

let pp fmt fname = Fmt.string fmt (toString fname)

module Set = Set.Make(struct
  type nonrec t = t
  let compare = compare
end)

module Map = Map.Make(struct
  type nonrec t = t
  let compare = compare
end)
