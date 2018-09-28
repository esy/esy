type t =
  | Npm of SemverVersion.Version.t
  | Opam of OpamPackageVersion.Version.t
  | Source of Source.t
  [@@deriving ord]

let show v =
  match v with
  | Npm t -> SemverVersion.Version.show t
  | Opam v -> "opam:" ^ OpamPackageVersion.Version.show v
  | Source src -> (Source.show src)

let pp fmt v =
  Fmt.fmt "%s" fmt (show v)

module Parse = struct
  include Parse

  let npm =
    let%map v = SemverVersion.Version.parser in
    Npm v

  let opam =
    let%map v = OpamPackageVersion.Version.parser in
    Opam v

  let opamWithPrefix =
    string "opam:" *> opam

  let source =
    let%map source = Source.parser in
    Source source
end

let parse ?(tryAsOpam=false) =
  let parser =
    if tryAsOpam
    then Parse.(source <|> opamWithPrefix <|> opam)
    else Parse.(source <|> opamWithPrefix <|> npm)
  in
  Parse.parse parser

let%test_module "parsing" = (module struct

  let expectParses = Parse.Test.expectParses ~pp ~compare

  let%test "1.0.0" =
    expectParses
      parse
      "1.0.0"
      (Npm (SemverVersion.Version.parseExn "1.0.0"))

  let%test "opam:1.0.0" =
    expectParses
      parse
      "opam:1.0.0"
      (Opam (OpamPackageVersion.Version.parseExn "1.0.0"))

  let%test "1.0.0" =
    expectParses
      (parse ~tryAsOpam:true)
      "1.0.0"
      (Opam (OpamPackageVersion.Version.parseExn "1.0.0"))

  let%test "1.0.0" =
    expectParses
      (parse ~tryAsOpam:true)
      "opam:1.0.0"
      (Opam (OpamPackageVersion.Version.parseExn "1.0.0"))

  let%test "no-source:" =
    expectParses
      parse
      "no-source:"
      (Source Source.NoSource)

  let%test "no-source:" =
    expectParses
      (parse ~tryAsOpam:true)
      "no-source:"
      (Source Source.NoSource)
end)

let parseExn v =
  match parse v with
  | Ok v -> v
  | Error err -> failwith err

let to_yojson v = `String (show v)

let of_yojson json =
  let open Result.Syntax in
  let%bind v = Json.Decode.string json in
  parse v

module Map = Map.Make(struct
  type nonrec t = t
  let compare = compare
end)

module Set = Set.Make(struct
  type nonrec t = t
  let compare = compare
end)
