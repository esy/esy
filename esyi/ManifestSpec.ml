open Sexplib0.Sexp_conv

module Filename = struct
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

end

type t =
  | One of Filename.t
  | ManyOpam
  [@@deriving ord, sexp_of]

let show = function
  | One fname -> Filename.show fname
  | ManyOpam -> "*.opam"

let pp fmt manifest =
  match manifest with
  | One fname -> Filename.pp fmt fname
  | ManyOpam -> Fmt.unit "*.opam" fmt ()

let to_yojson manifest =
  match manifest with
  | One (_, fname) -> `String fname
  | ManyOpam -> `String "*.opam"

let ofString v =
  let open Result.Syntax in
  match v with
  | "*.opam" -> return ManyOpam
  | v ->
    let%bind fname = Filename.ofString v in
    return (One fname)

let of_yojson json =
  let open Result.Syntax in
  match json with
  | `String v -> ofString v
  | _ -> errorf "invalid manifest spec: expected string"

let isOpamFilename filename =
  Path.(hasExt ".opam" (v filename)) || filename = "opam"

let findManifestsAtPath path spec =
  let open RunAsync.Syntax in
  match spec with
  | One (kind, filename) -> return [kind, filename]
  | ManyOpam ->
    let%bind filenames = Fs.listDir path in
    let f manifests filename =
      if isOpamFilename filename
      then (Filename.Opam, filename)::manifests
      else manifests
    in
    return (List.fold_left ~f ~init:[] filenames)

module Set = Set.Make(struct
  type nonrec t = t
  let compare = compare
end)

module Map = Map.Make(struct
  type nonrec t = t
  let compare = compare
end)
