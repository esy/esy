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
    | _, fname -> Some Path.(v fname |> remExt |> show)

end

type t =
  | One of Filename.t
  | ManyOpam of string list
  [@@deriving ord]

let show = function
  | One fname -> Filename.show fname
  | ManyOpam fnames -> String.concat "," fnames

let pp fmt manifest =
  match manifest with
  | One fname -> Filename.pp fmt fname
  | ManyOpam fnames -> Fmt.(list ~sep:(unit ", ") string) fmt fnames

let to_yojson manifest =
  match manifest with
  | One (_, fname) -> `String fname
  | ManyOpam fnames ->
    let fnames = List.map ~f:(fun fname -> `String fname) fnames in
    `List fnames

let of_yojson json =
  let open Result.Syntax in
  match json with
  | `String _ ->
    let%map fname = Filename.of_yojson json in
    One fname
  | `List fnames ->
    let%bind fnames =
      let f json =
        match json with
        | `String fname ->
          begin match Path.(getExt (v fname)) with
          | ".json" -> return fname
          | _ -> errorf "invalid opam manifest: %s" fname
          end
        | _ -> errorf "expected string"
      in
      Result.List.map ~f fnames
    in
    return (ManyOpam fnames)
  | _ -> errorf "invalid manifest spec"

module Set = Set.Make(struct
  type nonrec t = t
  let compare = compare
end)

module Map = Map.Make(struct
  type nonrec t = t
  let compare = compare
end)
