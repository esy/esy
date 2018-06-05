(* TODO: move this to another module *)
module Abstract = struct

  (**
  * Package version.
  *)
  module type VERSION = sig
    type t

    val equal : t -> t -> bool
    val compare : t -> t -> int
    val show : t -> string

    val parse : string -> (t, string) result
    val toString : t -> string
  end

end

(** opam versions are Debian-style versions *)
module Version = DebianVersion

(**
 * Npm formulas over opam versions.
 *)
module Formula = struct

  type t =
    Version.t GenericVersion.range
    [@@deriving to_yojson]

  let nextForCaret v =
    let next =
      match Version.AsSemver.major v with
      | Some 0 -> Version.AsSemver.nextPatch v
      | Some _ -> Version.AsSemver.nextMinor v
      | None -> None
    in match next with
    | Some next -> Ok next
    | None ->
      let msg = Printf.sprintf
        "unable to apply ^ version operator to %s"
        (Version.toString v)
      in
      Error msg

  let nextForTilde v =
    match Version.AsSemver.nextPatch v with
    | Some next -> Ok next
    | None ->
      let msg = Printf.sprintf
        "unable to apply ~ version operator to %s"
        (Version.toString v)
      in
      Error msg

  let parseRel text =
    let open Result.Syntax in
    match String.trim text with
    | "*"  | "" -> return GenericVersion.ANY
    | text ->
      begin match text.[0], text.[1] with
      | '^', _ ->
        let text = NpmVersion.Parser.sliceToEnd text 1 in
        let%bind v = Version.parse text in
        let%bind next = nextForCaret v in
        return GenericVersion.(AND ((GTE v), (LT next)))
      | '~', _ ->
        let text = NpmVersion.Parser.sliceToEnd text 1 in
        let%bind v = Version.parse text in
        let%bind next = nextForTilde v in
        return GenericVersion.(AND ((GTE v), (LT next)))
      | '=', _ ->
        let text = NpmVersion.Parser.sliceToEnd text 1 in
        let%bind v = Version.parse text in
        return (GenericVersion.EQ v)
      | '<', '=' ->
        let text = NpmVersion.Parser.sliceToEnd text 2 in
        let%bind v = Version.parse text in
        return (GenericVersion.LTE v)
      | '<', _ ->
        let text = NpmVersion.Parser.sliceToEnd text 1 in
        let%bind v = Version.parse text in
        return (GenericVersion.LT v)
      | '>', '=' ->
        let text = NpmVersion.Parser.sliceToEnd text 2 in
        let%bind v = Version.parse text in
        return (GenericVersion.GTE v)
      | '>', _ ->
        let text = NpmVersion.Parser.sliceToEnd text 1 in
        let%bind v = Version.parse text in
        return (GenericVersion.GT v)
      | _, _ ->
        let%bind v = Version.parse text in
        return (GenericVersion.EQ v)
      end

  (* TODO: do not use failwith here *)
  let parse v =
    let parseSimple v =
      let parse v =
        match parseRel v with
        | Ok v -> v
        | Error err -> failwith err
        in
      NpmVersion.Parser.parseSimples v parse
    in
    NpmVersion.Parser.parseOrs parseSimple v

  let matches = GenericVersion.matches Version.compare

  let toString v = GenericVersion.view Version.toString v

end
