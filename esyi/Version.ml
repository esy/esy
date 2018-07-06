module type VERSION  = sig
  type t
  val equal : t -> t -> bool
  val compare : t -> t -> int
  val show : t -> string
  val pp : Format.formatter -> t -> unit
  val parse : string -> (t, string) result
  val prerelease : t -> bool
  val stripPrerelease : t -> t
  val toString : t -> string
  val to_yojson : t -> Json.t
  val of_yojson : Json.t -> (t, string) result
end

(** Constraints over versions *)
module Constraint = struct
  module Make (Version: VERSION) = struct

    module VersionSet = Set.Make(Version)

    type t =
      | EQ of Version.t
      | NEQ of Version.t
      | GT of Version.t
      | GTE of Version.t
      | LT of Version.t
      | LTE of Version.t
      | NONE
      | ANY
      [@@deriving (yojson, eq)]

    let pp fmt = function
      | EQ v -> Fmt.pf fmt "=%a" Version.pp v
      | NEQ v -> Fmt.pf fmt "!=%a" Version.pp v
      | GT v -> Fmt.pf fmt ">%a" Version.pp v
      | GTE v -> Fmt.pf fmt ">=%a" Version.pp v
      | LT v -> Fmt.pf fmt "<%a" Version.pp v
      | LTE v -> Fmt.pf fmt "<=%a" Version.pp v
      | NONE -> Fmt.pf fmt "NONE"
      | ANY -> Fmt.pf fmt "*"

    let matchesSimple ~version constr =
      match constr with
      | EQ a -> Version.compare a version = 0
      | NEQ a -> Version.compare a version != 0
      | ANY -> true
      | NONE -> false

      | GT a -> Version.compare a version < 0
      | GTE a -> Version.compare a version <= 0
      | LT a -> Version.compare a version > 0
      | LTE a -> Version.compare a version >= 0

    let matches ?(matchPrerelease=VersionSet.empty) ~version constr  =
      match Version.prerelease version, constr with
      | _, EQ _
      | _, NEQ _
      | _, NONE
      | false, ANY
      | false, GT _
      | false, GTE _
      | false, LT _
      | false, LTE _ -> matchesSimple ~version constr

      | true, ANY
      | true, GT _
      | true, GTE _
      | true, LT _
      | true, LTE _ ->
        if VersionSet.mem (Version.stripPrerelease version) matchPrerelease
        then matchesSimple ~version constr
        else false

    let toString c =
      Format.asprintf "%a" pp c

    let show = toString

    let rec map ~f constr =
      match constr with
      | EQ a -> EQ (f a)
      | NEQ a -> NEQ (f a)
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
    module VersionSet = Constraint.VersionSet

    type 'f conj = 'f list [@@deriving (show, yojson, eq)]
    type 'f disj = 'f list [@@deriving (show, yojson, eq)]

    module DNF = struct
      type t =
        Constraint.t conj disj
        [@@deriving (yojson, eq)]

      let unit constr =
        [[constr]]

      let matches ~version (formulas) =
        let matchesConj (formulas) =
          (* Within each conjunction we allow prelease versions to be matched
           * but only those were mentioned in any of the constraints of the
           * conjunction, so that:
           *  1.0.0-alpha.2 matches >=1.0.0.alpha1
           *  1.0.0-alpha.2 does not match >=0.9.0
           *  1.0.0-alpha.2 does not match >=0.9.0 <2.0.0
           *)
          let matchPrerelease =
            let f vs = function
              | Constraint.NONE
              | Constraint.ANY -> vs
              | Constraint.EQ v
              | Constraint.NEQ v
              | Constraint.LTE v
              | Constraint.LT v
              | Constraint.GTE v
              | Constraint.GT v ->
                if Version.prerelease v
                then VersionSet.add (Version.stripPrerelease v) vs
                else vs
            in
            List.fold_left ~f ~init:VersionSet.empty formulas
          in
          List.for_all ~f:(Constraint.matches ~matchPrerelease ~version) formulas
        in
        List.exists ~f:matchesConj formulas

      let pp fmt f =
        let ppConj = Fmt.(list ~sep:(unit " && ") Constraint.pp) in
        Fmt.(list ~sep:(unit " || ") ppConj) fmt f

      let show f =
        Format.asprintf "%a" pp f

      let toString = show

      let rec map ~f formulas =
        let mapConj (formulas) =
          (List.map ~f:(Constraint.map ~f) formulas)
        in (List.map ~f:mapConj formulas)

      let conj a b =
        let items =
          let items = [] in
          let f items a =
            let f items b =
              ((a @ b)::items)
            in
            List.fold_left ~f ~init:items b
          in
          List.fold_left ~f ~init:items a
        in items

      let disj a b =
        (a @ b)

    end

    module CNF = struct
      [@@@ocaml.warning "-32"]
      type t =
        Constraint.t disj conj
        [@@deriving yojson]

      let pp fmt f =
        let ppDisj fmt = function
          | [] -> Fmt.unit "true" fmt ()
          | [disj] -> Constraint.pp fmt disj
          | disjs ->
            Fmt.pf fmt "(%a)" Fmt.(list ~sep:(unit " || ") Constraint.pp) disjs
        in
        Fmt.(list ~sep:(unit " && ") ppDisj) fmt f

      let show f =
        Format.asprintf "%a" pp f

      let toString = show

      let matches ~version (formulas) =
        let matchesDisj (formulas) =
          (* Within each conjunction we allow prelease versions to be matched
           * but only those were mentioned in any of the constraints of the
           * conjunction, so that:
           *  1.0.0-alpha.2 matches >=1.0.0.alpha1
           *  1.0.0-alpha.2 does not match >=0.9.0
           *  1.0.0-alpha.2 does not match >=0.9.0 <2.0.0
           *)
          let matchPrerelease =
            let f vs = function
              | Constraint.NONE
              | Constraint.ANY -> vs
              | Constraint.EQ v
              | Constraint.NEQ v
              | Constraint.LTE v
              | Constraint.LT v
              | Constraint.GTE v
              | Constraint.GT v ->
                if Version.prerelease v
                then VersionSet.add (Version.stripPrerelease v) vs
                else vs
            in
            List.fold_left ~f ~init:VersionSet.empty formulas
          in
          List.exists ~f:(Constraint.matches ~matchPrerelease ~version) formulas
        in
        List.for_all ~f:matchesDisj formulas
    end

    type constr = Constraint.t

    let ofDnfToCnf (f : DNF.t)  =
      let f : CNF.t =
        match f with
        | [] -> []
        | (constrs::conjs) ->
          let init : constr disj list = List.map ~f:(fun r -> [r]) constrs in
          let conjs =
            let addConj (cnf : constr disj list) conj =
              cnf
              |> List.map ~f:(fun constrs -> List.map ~f:(fun r -> r::constrs) conj)
              |> List.flatten
            in
            List.fold_left ~f:addConj ~init conjs
          in
          conjs
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
        List.map ~f:parse items

      let disjunction ~parse version =
        let version = String.trim version in
        let items = Str.split (Str.regexp " +|| +") version in
        let items = List.map ~f:parse items in
        let items =
          match items with
          | [] -> [[Constraint.ANY]]
          | items -> items
        in
        items
    end
  end
end

let%test_module "Formula" = (module struct

  module Version = struct
    type t = int [@@deriving yojson]
    let equal = (=)
    let compare = compare
    let pp = Fmt.int
    let show = string_of_int
    let prerelease _ = false
    let stripPrerelease v = v
    let parse v =
      match int_of_string_opt v with
      | Some v -> Ok v
      | None -> Error "not a version"
    let toString = string_of_int
  end

  module F = Formula.Make(Version)
  module C = F.Constraint
  open C

  let%test "ofDnfToCnf: 1" =
    F.ofDnfToCnf ([[C.EQ 1]]) = [[EQ 1]]

  let%test "ofDnfToCnf: 1 && 2" =
    F.ofDnfToCnf ([[EQ 1; EQ 2]]) = [[EQ 1]; [EQ 2]]

  let%test "ofDnfToCnf: 1 && 2 || 3" =
    F.ofDnfToCnf ([[EQ 1; EQ 2]; [EQ 3]])
    = [[EQ 3; EQ 1]; [EQ 3; EQ 2]]

  let%test "ofDnfToCnf: 1 && 2 || 3 && 4" =
    F.ofDnfToCnf ([[EQ 1; EQ 2]; [EQ 3; EQ 4]])
    = [[EQ 3; EQ 1]; [EQ 4; EQ 1]; [EQ 3; EQ 2]; [EQ 4; EQ 2]]
end)
