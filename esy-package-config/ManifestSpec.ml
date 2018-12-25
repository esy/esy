open Sexplib0.Sexp_conv

type t = kind * string
  [@@deriving ord, sexp_of]

and kind =
  | Esy
  | Opam

let show (_, fname) = fname

let pp fmt (_, fname) = Fmt.string fmt fname

let ofString fname =
  let open Result.Syntax in
  match fname with
  | "" -> errorf "empty filename"
  | "opam" -> return (Opam, "opam")
  | fname ->
    begin match Path.(getExt (v fname)) with
    | ".json" -> return (Esy, fname)
    | ".opam" -> return (Opam, fname)
    | _ -> errorf "invalid manifest: %s" fname
    end

let ofStringExn fname =
  match ofString fname with
  | Ok fname -> fname
  | Error msg -> failwith msg

let parser =
  let make fname =
    match ofString fname with
    | Ok fname -> Parse.return fname
    | Error msg -> Parse.fail msg
  in
  Parse.(take_while1 (fun _ -> true) >>= make)

let to_yojson (_, fname) = `String fname

let of_yojson json =
  let open Result.Syntax in
  match json with
  | `String "opam" -> return (Opam, "opam")
  | `String fname -> ofString fname
  | _ -> error "invalid manifest filename"

let inferPackageName = function
  | Opam, "opam" -> None
  | Opam, fname -> Some ("@opam/" ^ Path.(v fname |> remExt |> show))
  | Esy, fname -> Some Path.(v fname |> remExt |> show)
