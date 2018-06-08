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

(** Constraints over versions *)
module Constraint = struct
  module Make (Version: VERSION) = struct
    type t =
      | EQ of Version.t
      | GT of Version.t
      | GTE of Version.t
      | LT of Version.t
      | LTE of Version.t
      | NONE
      | ANY
      [@@deriving yojson]

    let matches ~version constr  =
      match constr with
      | EQ a -> Version.compare a version = 0
      | ANY -> true
      | NONE -> false
      | GT a -> Version.compare a version < 0
      | GTE a -> Version.compare a version <= 0
      | LT a -> Version.compare a version > 0
      | LTE a -> Version.compare a version >= 0

    let isTooLarge ~version constr =
      match constr with
      | EQ a -> Version.compare a version < 0
      | ANY -> false
      | NONE -> false
      | GT _a -> false
      | GTE _a -> false
      | LT a -> Version.compare a version <= 0
      | LTE a -> Version.compare a version < 0

    let rec toString constr =
      match constr with
      | EQ a -> Version.toString a
      | ANY -> "*"
      | NONE -> "none"
      | GT a -> "> " ^ Version.toString a
      | GTE a -> ">= " ^ Version.toString a
      | LT a -> "< " ^ Version.toString a
      | LTE a -> "<= " ^ Version.toString a

    let rec map ~f constr =
      match constr with
      | EQ a-> EQ (f a)
      | ANY -> ANY
      | NONE -> NONE
      | GT a -> GT (f a)
      | GTE a -> GTE (f a)
      | LT a -> LT (f a)
      | LTE a -> LTE (f a)

  end
end

module Formula = struct

  module Make (Version: VERSION) = struct

    module Constraint = Constraint.Make(Version)

    type 'f conj = AND of 'f list [@@deriving yojson]
    type 'f disj = OR of 'f list [@@deriving yojson]

    let any cond formulas =
      List.exists cond formulas

    let rec every cond = function
      | f::rest -> if cond f then every cond rest else false
      | [] -> true

    module DNF = struct
      type t =
        Constraint.t conj disj
        [@@deriving yojson]

      let matches ~version (OR formulas) =
        let matchesConj (AND formulas) =
          every (Constraint.matches ~version) formulas
        in
        any matchesConj formulas

      let isTooLarge ~version (OR formulas) =
        let matchesConj (AND formulas) =
          every (Constraint.isTooLarge ~version) formulas
        in
        any matchesConj formulas

      let rec toString (OR formulas) =
        formulas
        |> List.map (fun (AND formulas) ->
          formulas
          |> List.map Constraint.toString
          |> String.concat " && ")
        |> String.concat " || "

      let rec map ~f (OR formulas) =
        let mapConj (AND formulas) =
          AND (List.map (Constraint.map ~f) formulas)
        in OR (List.map mapConj formulas)

      let conj (OR a) (OR b) =
        let items =
          let items = [] in
          let f items (AND a) =
            let f items (AND b) =
              (AND (a @ b)::items)
            in
            ListLabels.fold_left ~f ~init:items b
          in
          ListLabels.fold_left ~f ~init:items a
        in OR items

      let disj (OR a) (OR b) =
        OR (a @ b)

    end

    module CNF = struct
      type t =
        Constraint.t disj conj
        [@@deriving yojson]
    end

    type dnf = DNF.t
    type cnf = CNF.t

    module Parse = struct
      let conjunction ~parse item =
        let item =
          item
          |> Str.global_replace (Str.regexp ">= +") ">="
          |> Str.global_replace (Str.regexp "<= +") "<="
          |> Str.global_replace (Str.regexp "> +") ">"
          |> Str.global_replace (Str.regexp "< +") "<"
        in
        let items = String.split_on_char ' ' item in
        AND (List.map parse items)

      let disjunction ~parse version =
        let items = Str.split (Str.regexp " +|| +") version in
        OR (List.map parse items)
    end
  end
end
