module type VERSION  = sig
  type t
  val equal : t -> t -> bool
  val compare : t -> t -> int
  val show : t -> string
  val parse : string -> (t, string) result
  val toString : t -> string
  val to_yojson : t -> Json.t
  val of_yojson : Json.t -> (t, string) result
end

module Formula = struct
  module Make (Version: VERSION) = struct
    type t =
      | OR of t * t
      | AND of t * t
      | EQ of Version.t
      | GT of Version.t
      | GTE of Version.t
      | LT of Version.t
      | LTE of Version.t
      | NONE
      | ANY [@@deriving yojson]

    let rec matches formula version =
      match formula with
      | EQ a -> Version.compare a version = 0
      | ANY -> true
      | NONE -> false
      | GT a -> Version.compare a version < 0
      | GTE a -> Version.compare a version <= 0
      | LT a -> Version.compare a version > 0
      | LTE a -> Version.compare a version >= 0
      | AND (a, b) -> matches a version && matches b version
      | OR (a, b) -> matches a version || matches b version

    let rec isTooLarge formula version =
      match formula with
      | EQ a -> Version.compare a version < 0
      | ANY -> false
      | NONE -> false
      | GT _a -> false
      | GTE _a -> false
      | LT a -> Version.compare a version <= 0
      | LTE a -> Version.compare a version < 0
      | AND (a, b) -> isTooLarge a version || isTooLarge b version
      | OR (a, b) -> isTooLarge a version && isTooLarge b version

    let rec toString range =
      match range with
      | EQ a -> Version.toString a
      | ANY -> "*"
      | NONE -> "none"
      | GT a -> "> " ^ Version.toString a
      | GTE a -> ">= " ^ Version.toString a
      | LT a -> "< " ^ Version.toString a
      | LTE a -> "<= " ^ Version.toString a
      | AND (a, b) -> toString a ^ " && " ^ toString b
      | OR (a, b)-> toString a ^ " || " ^ toString b

    let rec map transform range =
      match range with
      | EQ a-> EQ (transform a)
      | ANY -> ANY
      | NONE -> NONE
      | GT a -> GT (transform a)
      | GTE a -> GTE (transform a)
      | LT a -> LT (transform a)
      | LTE a -> LTE (transform a)
      | AND (a, b) -> AND (map transform a, map transform b)
      | OR (a, b) -> OR (map transform a, map transform b)

    module Parse = struct
      let conjunction parse item =
        let item =
          item
          |> Str.global_replace (Str.regexp ">= +") ">="
          |> Str.global_replace (Str.regexp "<= +") "<="
          |> Str.global_replace (Str.regexp "> +") ">"
          |> Str.global_replace (Str.regexp "< +") "<"
        in
        let items = String.split_on_char ' ' item in
        let rec loop items =
          match items with
          | item::[] -> parse item
          | item::items -> AND (parse item, loop items)
          | [] -> assert false in
        loop items

      let disjunction parse version =
        if version = ""
        then ANY
        else
          let items = Str.split (Str.regexp " +|| +") version in
          let rec loop items =
            match items with
            | [] ->
                failwith ((("WAAAT ")[@reason.raw_literal "WAAAT "]) ^ version)
            | item::[] -> parse item
            | item::items -> ((OR ((parse item), (loop items)))[@explicit_arity ]) in
          loop items
    end
  end
end
