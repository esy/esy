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
      List.exists ~f:cond formulas

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
        |> List.map ~f:(fun (AND formulas) ->
          formulas
          |> List.map ~f:Constraint.toString
          |> String.concat " && ")
        |> String.concat " || "

      let show = toString

      let rec map ~f (OR formulas) =
        let mapConj (AND formulas) =
          AND (List.map ~f:(Constraint.map ~f) formulas)
        in OR (List.map ~f:mapConj formulas)

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

      let rec toString (AND formulas) =
        formulas
        |> List.map ~f:(fun (OR formulas) ->
          let formulas =
          formulas
          |> List.map ~f:Constraint.toString
          |> String.concat " || "
          in "(" ^ formulas ^ ")")
        |> String.concat " && "

      let show = toString
    end

    type constr = Constraint.t
    type dnf = DNF.t
    type cnf = CNF.t

    let ofDnfToCnf (f : dnf)  =
      let f : cnf =
        match f with
        | OR [] -> AND []
        | OR ((AND constrs)::conjs) ->
          let init : constr disj list = List.map ~f:(fun r -> OR [r]) constrs in
          let conjs =
            let addConj (cnf : constr disj list) (AND conj) =
              cnf
              |> List.map ~f:(fun (OR constrs) -> List.map ~f:(fun r -> OR (r::constrs)) conj)
              |> List.flatten
            in
            ListLabels.fold_left ~f:addConj ~init conjs
          in
          AND conjs
      in f

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
        AND (List.map ~f:parse items)

      let disjunction ~parse version =
        let items = Str.split (Str.regexp " +|| +") version in
        OR (List.map ~f:parse items)
    end
  end
end

let%test_module "Formula" = (module struct

  module Version = struct
    type t = int [@@deriving yojson]
    let equal = (=)
    let compare = compare
    let show = string_of_int
    let parse v =
      match int_of_string_opt v with
      | Some v -> Ok v
      | None -> Error "not a version"
    let toString = string_of_int
  end

  module F = Formula.Make(Version)
  module C = F.Constraint
  open C
  open F

  let%test "ofDnfToCnf: 1" =
    F.ofDnfToCnf (OR [AND [C.EQ 1]]) = AND [OR [EQ 1]]

  let%test "ofDnfToCnf: 1 && 2" =
    F.ofDnfToCnf (OR [AND [EQ 1; EQ 2]]) = AND [OR [EQ 1]; OR[EQ 2]]

  let%test "ofDnfToCnf: 1 && 2 || 3" =
    F.ofDnfToCnf (OR [AND [EQ 1; EQ 2]; AND [EQ 3]])
    = AND [OR [EQ 3; EQ 1]; OR[EQ 3; EQ 2]]

  let%test "ofDnfToCnf: 1 && 2 || 3 && 4" =
    F.ofDnfToCnf (OR [AND [EQ 1; EQ 2]; AND [EQ 3; EQ 4]])
    = AND [OR [EQ 3; EQ 1]; OR [EQ 4; EQ 1]; OR [EQ 3; EQ 2]; OR [EQ 4; EQ 2]]
end)
