type part = Digest.t

let part_to_yojson v = Json.Encode.string(Digest.to_hex(v))
let part_of_yojson json =
  let open Result.Syntax in
  let%bind part = Json.Decode.string json in
  return (Digest.from_hex part)

type t = part list

let empty = []

let string v = Digest.string v
let json v = string (Yojson.Safe.to_string v)

let add part digest = part::digest

let combine a b = a @ b
let (+) = combine

let toHex digest =
  digest
  |> List.map ~f:Digest.to_hex
  |> String.concat "$$"
  |> Digest.string
  |> Digest.to_hex
