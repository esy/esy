type t =
| Esy of string
| Opam of string
| OpamAggregated of string list
[@@deriving ord]

let show = function
  | Esy fname
  | Opam fname -> fname
  | OpamAggregated fnames -> String.concat "," fnames

let pp fmt manifest =
  match manifest with
  | Esy fname | Opam fname -> Fmt.string fmt fname
  | OpamAggregated fnames -> Fmt.(list ~sep:(unit ", ") string) fmt fnames

let ofString fname =
  (* this deliberately doesn't handle OpamAggregated *)
  let open Result.Syntax in
  match fname with
  | "" -> errorf "empty filename"
  | "opam" -> return (Opam "opam")
  | fname ->
    begin match Path.(getExt (v fname)) with
    | ".json" -> return (Esy fname)
    | ".opam" -> return (Opam fname)
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

let to_yojson manifest =
  match manifest with
  | Esy fname | Opam fname -> `String fname
  | OpamAggregated fnames ->
    let fnames = List.map ~f:(fun fname -> `String fname) fnames in
    `List fnames

let of_yojson json =
  let open Result.Syntax in
  match json with
  | `String "opam" -> return (Opam "opam")
  | `String fname -> ofString fname
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
    return (OpamAggregated fnames)
  | _ -> errorf "invalid manifest"

module Set = Set.Make(struct
  type nonrec t = t
  let compare = compare
end)

module Map = Map.Make(struct
  type nonrec t = t
  let compare = compare
end)
