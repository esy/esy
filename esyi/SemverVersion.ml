module MakeFormula = Version.Formula.Make
module MakeConstraint = Version.Constraint.Make

module Version = struct
  type t = {
    major : int;
    minor : int;
    patch : int;
    prerelease : prerelease;
    build : build;
  } [@@deriving (eq, yojson)]

  and prerelease = segment list

  and build = string list

  and segment =
    | W of string
    | N of int

  let ppSegment fmt = function
    | W v -> Fmt.string fmt v
    | N v -> Fmt.int fmt v

  let ppPrerelease = Fmt.(list ~sep:(unit ".") ppSegment)

  let ppBuild = Fmt.(list ~sep:(unit ".") string)

  let compareSegment a b =
    match a, b with
    | N _, W _ -> -1
    | W _, N _ -> 1
    | N a, N b -> compare a b
    | W a, W b -> String.compare a b

  let make ?(prerelease=[]) ?(build=[]) major minor patch =
    {major; minor; patch; prerelease; build}

  let toString v =
    let prelease = match v.prerelease with
    | [] -> ""
    | v -> Format.asprintf "-%a" ppPrerelease v
    in
    let build = match v.build with
    | [] -> ""
    | v -> Format.asprintf "+%a" ppBuild v
    in
    Format.asprintf "%i.%i.%i%s%s" v.major v.minor v.patch prelease build

  let show = toString

  let pp fmt v =
    Fmt.pf fmt "npm:%s" (toString v)

  let prerelease v = match v.prerelease, v.build with
  | [], [] -> false
  | _, _ -> true

  let stripPrerelease v = {v with prerelease = []; build = []}

  module Parse = struct
    open Re
    let dot = char '.'
    let dash = char '-'
    let plus = char '+'
    let section = group (rep1 digit)
    let prereleaseChar = alt [alnum; char '-'; char '.']
    let prerelease = opt (seq [opt dash; group (rep1 prereleaseChar)])
    let build = opt (seq [opt plus; group (rep1 prereleaseChar)])
    let prefix = rep (alt [char 'v'; char '='])

    let version3 = compile (seq [
      bos;
      prefix;
      section;
      dot;
      section;
      dot;
      section;
      prerelease;
      build;
      eos;
    ])

    let version2 = compile (seq [
      bos;
      prefix;
      section;
      dot;
      section;
      prerelease;
      build;
      eos;
    ])

    let version1 = compile (seq [
      bos;
      prefix;
      section;
      prerelease;
      build;
      eos;
    ])

    let prerelaseAndBuild = compile (seq [
      bos;
      prerelease;
      build;
      eos;
    ])
  end

  let intAtExn n m =
    let v = Re.Group.get m n in
    int_of_string v

  let optStrignAt n m =
    match Re.Group.get m n with
    | exception Not_found -> None
    | "" -> None
    | v -> Some v

  let parsePrerelease v =
    v
    |> String.split_on_char '.'
    |> List.map ~f:(fun v -> try N (int_of_string v) with _ -> W v)

  let parseBuild v =
    String.split_on_char '.' v

  let parsePrerelaseAndBuild v =
    match Re.exec_opt Parse.prerelaseAndBuild v with
    | Some m ->
      let prerelease = match optStrignAt 1 m with
      | Some v -> parsePrerelease v
      | None -> []
      in
      let build = match optStrignAt 2 m with
      | Some v -> parseBuild v
      | None -> []
      in
      Ok (prerelease, build)
    | None ->
      let msg = Printf.sprintf "unable to prerelease and build: %s" v in
      Error msg

  let parse version =
    match Re.exec_opt Parse.version3 version with
    | Some m ->
      let major = intAtExn 1 m in
      let minor = intAtExn 2 m in
      let patch = intAtExn 3 m in
      let prerelease = match optStrignAt 4 m with
      | Some v -> parsePrerelease v
      | None -> []
      in
      let build = match optStrignAt 5 m with
      | Some v -> parseBuild v
      | None -> []
      in
      Ok {major; minor; patch; prerelease; build}
    | None -> begin match Re.exec_opt Parse.version2 version with
      | Some m ->
        let major = intAtExn 1 m in
        let minor = intAtExn 2 m in
        let prerelease = match optStrignAt 3 m with
        | Some v -> parsePrerelease v
        | None -> []
        in
        let build = match optStrignAt 4 m with
        | Some v -> parseBuild v
        | None -> []
        in
        Ok {major; minor; patch = 0; prerelease; build}
      | None -> begin match Re.exec_opt Parse.version1 version with
        | Some m ->
          let major = intAtExn 1 m in
          let prerelease = match optStrignAt 2 m with
          | Some v -> parsePrerelease v
          | None -> []
          in
          let build = match optStrignAt 3 m with
          | Some v -> parseBuild v
          | None -> []
          in
          Ok {major; minor = 0; patch = 0; prerelease; build}
        | None ->
          let msg = Printf.sprintf "invalid semver version: '%s'" version in
          Error msg
        end
      end

  let parseExn v =
    match parse v with
    | Ok v -> v
    | Error err -> raise (Invalid_argument err)

  let%test_module "parse" = (module struct

    let expectParsesTo v e =
      let p = parse v in
      match e, p with
      | Error _, Error _ -> true
      | Ok e, Ok p ->
        if equal p e
        then true
        else (
          Format.printf
            "@[<v 2>Failed to parse: %s@\nexpected: %a@\n     got: %a@]@\n"
            v pp e pp p;
          false
        )
      | Error _, Ok p ->
        Format.printf
          "@[<v 2>Expected to error but it parses: %s@\nas: %a@]@\n"
          v pp p;
        false
      | Ok e, Error _ ->
        Format.printf
          "@[<v 2>Expected to parse but it errors: %s@\nexpected: %a@]@\n"
          v pp e;
        false

    let cases = [
      "1.1.1", Ok (make 1 1 1);
      "1.1", Ok (make 1 1 0);
      "1", Ok (make 1 0 0);
      "1.1.1-alpha.29", Ok (make ~prerelease:[W "alpha"; N 29] 1 1 1);
      "1.1-alpha.29", Ok (make ~prerelease:[W "alpha"; N 29] 1 1 0);
      "1-alpha.29", Ok (make ~prerelease:[W "alpha"; N 29] 1 0 0);
      "v1.1.1", Ok (make 1 1 1);
      "v1.1", Ok (make 1 1 0);
      "v1", Ok (make 1 0 0);
      "=1.1.1", Ok (make 1 1 1);
      "=1.1", Ok (make 1 1 0);
      "=1", Ok (make 1 0 0);
      "==1.1.1", Ok (make 1 1 1);
      "=v1.1.1", Ok (make 1 1 1);
      "=vv1.1.1", Ok (make 1 1 1);
      "==vv1.1.1", Ok (make 1 1 1);
      "1.1.1alpha.29", Ok (make ~prerelease:[W "alpha"; N 29] 1 1 1);
      "1.1.1-alpha.029", Ok (make ~prerelease:[W "alpha"; N 29] 1 1 1);
      "1.1.1-alpha.29+1.a", Ok (make ~prerelease:[W "alpha"; N 29] ~build:["1"; "a"] 1 1 1);
      "1.1-alpha.29+1.a", Ok (make ~prerelease:[W "alpha"; N 29] ~build:["1"; "a"] 1 1 0);
      "1-alpha.29+1.a", Ok (make ~prerelease:[W "alpha"; N 29] ~build:["1"; "a"] 1 0 0);
      "1.1.1+1.a", Ok (make ~build:["1"; "a"] 1 1 1);
      "1.1+1.a", Ok (make ~build:["1"; "a"] 1 1 0);
      "1+1.a", Ok (make ~build:["1"; "a"] 1 0 0);
      "1.1.1+001.002", Ok (make ~build:["001"; "002"] 1 1 1);
      "a", Error "err";
      "1._", Error "err";
    ]

    let%test "parsing" =
      let f passes (v, e) =
        passes && (expectParsesTo v e)
      in
      List.fold_left ~f ~init:true cases

  end)

  let comparePrerelease (a : segment list) (b : segment list) =
    let rec compare a b =
      match a, b with
      | [], [] -> 0
      | [], _ -> -1
      | _, [] -> 1
      | x::xs, y::ys ->
        begin match compareSegment x y with
        | 0 -> compare xs ys
        | v -> v
        end
    in
    match a, b with
    | [], [] -> 0
    | [], _ -> 1
    | _, [] -> -1
    | a, b -> compare a b

  let compareBuild (a : string list) (b : string list) =
    let rec compare a b =
      match a, b with
      | [], [] -> 0
      | [], _ -> -1
      | _, [] -> 1
      | x::xs, y::ys ->
        begin match String.compare x y with
        | 0 -> compare xs ys
        | v -> v
        end
    in
    match a, b with
    | [], [] -> 0
    | [], _ -> 1
    | _, [] -> -1
    | a, b -> compare a b

  let compare a b =
    match a.major - b.major with
    | 0 -> begin
      match a.minor - b.minor with
        | 0 -> begin
          match a.patch - b.patch with
          | 0 -> begin
            match comparePrerelease a.prerelease b.prerelease with
            | 0 -> compareBuild a.build b.build
            | v -> v
            end
          | v -> v
        end
        | v -> v
    end
    | v -> v

  let%test_module "compare" = (module struct

    let ppOp = function
      | 0 -> "="
      | n when n > 0 -> ">"
      | _ -> "<"

    let expectComparesAs a b e =
      let a = parseExn a in
      let b = parseExn b in
      let c1 = compare a b in
      let c2 = compare b a in
      if c1 = e && c2 = -e
      then true
      else (
        Format.printf
          "@[<v 2>Failed to compare:@\nexpected: %a %s %a@\n     got: %a %s %a@]@\n"
          pp a (ppOp e) pp b pp a (ppOp c1) pp b;
        false
      )

    let cases = [
      "1.0.0", "2.0.0", -1;
      "2.0.0", "1.0.0", 1;

      "1.0.0", "1.0.0", 0;

      "1.1.0", "1.0.0", 1;
      "1.0.0", "1.1.0", -1;

      "1.1.0", "1.1.0", 0;

      "1.1.1", "1.1.0", 1;
      "1.1.0", "1.1.1", -1;

      "1.1.1", "1.1.1", 0;

      "1.1.1-alpha", "1.1.1", -1;
      "1.1.1", "1.1.1-alpha", 1;

      "1.1.1-alpha", "1.1.1-alpha", 0;

      "1.1.1-alpha.1", "1.1.1-alpha", 1;
      "1.1.1-alpha", "1.1.1-alpha.1", -1;

      "1.1.1-alpha.1", "1.1.1-alpha.1", 0;

      "1.1.1-alpha.2", "1.1.1-alpha.1", 1;
      "1.1.1-alpha.1", "1.1.1-alpha.2", -1;

      "1.1.1-alpha.1", "1.1.1-alpha.a", -1;
      "1.1.1-alpha.a", "1.1.1-alpha.1", 1;

      "1.1.1-alpha", "1.1.1-alpha.a", -1;
      "1.1.1-alpha.a", "1.1.1-alpha", 1;

      "1.1.1-alpha", "1.1.1-beta", -1;
      "1.1.1-beta", "1.1.1-alpha", 1;

      "1.1.1-alpha+1", "1.1.1-alpha+1", 0;
      "1.1.1-alpha+2", "1.1.1-alpha+1", 1;
      "1.1.1-alpha+1", "1.1.1-alpha+2", -1;

      "1.1.1", "1.1.1+1", 1;
      "1.1.1+1", "1.1.1", -1;

      "1.1.1+1", "1.1.1+1", 0;
      "1.1.1+2", "1.1.1+1", 1;
      "1.1.1+1", "1.1.1+2", -1;

      "1.1.1+1.2", "1.1.1+1", 1;
      "1.1.1+1", "1.1.1+1.2", -1;
    ]

    let%test "comparing" =
      let f passes (a, b, e) =
        passes && expectComparesAs a b e
      in
      List.fold_left ~f ~init:true cases

  end)

end

module Constraint = MakeConstraint(Version)

module Formula = struct
  include MakeFormula(Version)

  let any: DNF.t = [[Constraint.ANY]]

  module Parser = struct
    let sliceToEnd text num =
      String.sub text num ((String.length text) - num)

    let isint v = try ignore (int_of_string v); true with | _ -> false

    let getRest parts =
      match parts = [] with
      | true -> None
      | false -> Some (String.concat "." parts)

    let splitRest value =
      try
        match String.split_on_char '-' value with
        | _single::[] ->
          (match String.split_on_char '+' value with
            | _single::[] ->
              (match String.split_on_char '~' value with
              | single::[] -> int_of_string single, None
              | single::rest -> int_of_string single, Some ("~" ^ String.concat "~" rest)
              | _ -> 0, Some value)
            | single::rest -> int_of_string single, Some ("+" ^ String.concat "+" rest)
            | _ -> 0, Some value)
        | single::rest -> int_of_string single, Some ("-" ^ String.concat "-" rest)
        | _ -> 0, Some value
      with
      | _ -> 0, Some value

    let parsePrerelaseAndBuild v =
      match Version.parsePrerelaseAndBuild v with
      | Ok v -> v
      | Error err -> failwith err

    let exactPartial partial =
      match partial with
      | `AllStar -> failwith "* cannot be compared"
      | `MajorStar major -> Version.make major 0 0
      | `MinorStar (major, minor) -> Version.make major minor 0
      | `Major (major, prerelease, build) ->
        Version.make ~prerelease ~build major 0 0
      | `Minor (major, minor, prerelease, build) ->
        Version.make ~prerelease ~build major minor 0
      | `Patch (major, minor, patch, prerelease, build) ->
        Version.make ~prerelease ~build major minor patch
      | `Raw (prerelease, build) -> Version.make ~prerelease ~build 0 0 0

    let parsePartial version =
      let version =
        match version.[0] = 'v' with
        | true -> sliceToEnd version 1
        | false -> version
      in
      let parts = String.split_on_char '.' version in
      match parts with

      | ("*" | "x" | "X")::_rest ->
        `AllStar
      | major::("*" | "x" | "X")::_rest when isint major ->
        `MajorStar (int_of_string major)
      | major::minor::("*" | "x" | "X")::_rest when isint major && isint minor ->
        `MinorStar (int_of_string major, int_of_string minor)

      | _ ->
        let rx =
          Str.regexp
            {|^ *\([0-9]+\)\(\.\([0-9]+\)\(\.\([0-9]+\)\)?\)?\(\([-+~][a-z0-9\.]+\)\)?|}
        in begin
        match Str.search_forward rx version 0 with
          | exception Not_found -> `Raw (parsePrerelaseAndBuild version)
          | _ ->
            let major = int_of_string (Str.matched_group 1 version) in
            let prerelease, build =
              match Str.matched_group 7 version with
              | exception Not_found ->
                let last = Str.match_end () in
                if last < String.length version
                then parsePrerelaseAndBuild (sliceToEnd version last)
                else [], []
              | text -> parsePrerelaseAndBuild text
            in begin
            match Str.matched_group 3 version with
            | exception Not_found ->
              `Major (major, prerelease, build)
            | minor ->
              let minor = int_of_string minor in begin
              match Str.matched_group 5 version with
                | exception Not_found -> `Minor (major, minor, prerelease, build)
                | patch -> `Patch (major, minor, (int_of_string patch), prerelease, build)
              end
            end
        end

    let parsePrimitive item =
      match item.[0] with
      | '=' ->
        Constraint.EQ (exactPartial (parsePartial (sliceToEnd item 1)))
      | '>' -> begin
        match item.[1] with
        | '=' ->
          Constraint.GTE (exactPartial (parsePartial (sliceToEnd item 2)))
        | _ ->
          Constraint.GT (exactPartial (parsePartial (sliceToEnd item 1)))
        end
      | '<' -> begin
        match item.[1] with
        | '=' ->
          Constraint.LTE (exactPartial (parsePartial (sliceToEnd item 2)))
        | _ ->
          Constraint.LT (exactPartial (parsePartial (sliceToEnd item 1)))
        end
      | _ ->
        let msg = Printf.sprintf "bad version: %s" item in
        failwith msg

    let parseSimple item =
      match item.[0] with
      | '~' -> begin
        match parsePartial (sliceToEnd item 1) with
        | `Major (m, prerelease, build) ->
          [
            Constraint.GTE (Version.make ~prerelease ~build m 0 0);
            Constraint.LT (Version.make (m + 1) 0 0);
          ]
        | `Minor (m, i, prerelease, build) ->
          [
            Constraint.GTE (Version.make ~prerelease ~build m i 0);
            Constraint.LT (Version.make m (i + 1) 0);
          ]
        | `Patch (m, i, p, prerelease, build) ->
          [
            Constraint.GTE (Version.make ~prerelease ~build m i p);
            Constraint.LT (Version.make m (i + 1) 0);
          ]
        | `AllStar ->
          failwith "* cannot be tilded"
        | `MajorStar m ->
          [
            Constraint.GTE (Version.make m 0 0);
            Constraint.LT (Version.make (m + 1) 0 0);
          ]
        | `MinorStar (m, i) ->
          [
            Constraint.GTE (Version.make m i 0);
            Constraint.LT (Version.make m (i + 1) 0);
          ]
        | `Raw _ ->
          failwith "Bad tilde"
        end

      | '^' -> begin
        match parsePartial (sliceToEnd item 1) with
        | `Major (m, prerelease, build) ->
          [
            GTE (Version.make ~prerelease ~build m 0 0);
            LT (Version.make (m + 1) 0 0);
          ]
        | `Minor (0, i, prerelease, build) ->
          [
            GTE (Version.make ~prerelease ~build 0 i 0);
            LT (Version.make 0 (i + 1) 0);
          ]
        | `Minor (m, i, prerelease, build) ->
          [
            GTE (Version.make ~prerelease ~build m i 0);
            LT (Version.make (m + 1) 0 0);
          ]
        | `Patch (0, 0, p, prerelease, build) ->
          [
            GTE (Version.make ~prerelease ~build 0 0 p);
            LT (Version.make 0 0 (p + 1));
          ]
        | `Patch (0, i, p, prerelease, build) ->
          [
            GTE (Version.make ~prerelease ~build 0 i p);
            LT (Version.make 0 (i + 1) 0);
          ]
        | `Patch (m, i, p, prerelease, build) ->
          [
            GTE (Version.make ~prerelease ~build m i p);
            LT (Version.make (m + 1) 0 0);
          ]
        | `AllStar -> failwith "* cannot be careted"
        | `MajorStar m ->
          [
            GTE (Version.make m 0 0);
            LT (Version.make (m + 1) 0 0);
          ]
        | `MinorStar (m, i) ->
          [
            GTE (Version.make m i 0);
            LT (Version.make (m + 1) i 0);
          ]
        | `Raw _ -> failwith "Bad tilde"
      end

      | '>'|'<'|'=' -> [parsePrimitive item]

      | _ ->
        begin match parsePartial item with
          | `AllStar -> [ANY]
          | `Major (m, [], [])
          | `MajorStar m ->
            [
              GTE (Version.make m 0 0);
              LT (Version.make (m + 1) 0 0);
            ]
          | `Major (m, prerelease, build) ->
            [EQ (Version.make ~prerelease ~build m 0 0)]
          | `Minor (m, i, [], [])
          |`MinorStar (m, i) ->
            [
              GTE (Version.make m i 0);
              LT (Version.make m (i + 1) 0);
            ]
          | `Minor (m, i, prerelease, build) ->
            [ EQ (Version.make ~prerelease ~build m i 0)]
          | `Patch (m, i, p, prerelease, build) ->
            [EQ (Version.make ~prerelease ~build m i p)]
          | `Raw (prerelease, build) ->
            [EQ (Version.make ~prerelease ~build 0 0 0)]
        end

    let parseConj v =
      let vs = Str.split (Str.regexp " +") v in
      let vs =
        let f vs v = vs @ (parseSimple v) in
        List.fold_left ~f ~init:[] vs
      in
      vs

    let parseNpmRange v =
      let v =
        v
        |> Str.global_replace (Str.regexp ">= +") ">="
        |> Str.global_replace (Str.regexp "<= +") "<="
        |> Str.global_replace (Str.regexp "> +") ">"
        |> Str.global_replace (Str.regexp "< +") "<"
        |> Str.global_replace (Str.regexp "= +") "="
        |> Str.global_replace (Str.regexp "~ +") "~"
        |> Str.global_replace (Str.regexp "^ +") "^"
      in
      let vs = Str.split (Str.regexp " +- +") v in
      match vs with
      | item::[] -> parseConj item
      | left::right::[] ->
        let left = Constraint.GTE (parsePartial left |> exactPartial) in
        let right =
          match parsePartial right with
          | `AllStar -> Constraint.ANY
          | `Major (m, _, _)
          | `MajorStar m ->
            Constraint.LT (Version.make (m + 1) 0 0)
          | `Minor (m, i, _, _)
          | `MinorStar (m, i) ->
            Constraint.LT (Version.make m (i + 1) 0)
          | `Patch (m, i, p, prerelease, build) ->
            Constraint.LTE (Version.make ~prerelease ~build m i p)
          | `Raw (prerelease, build) ->
            Constraint.LT (Version.make ~prerelease ~build 0 0 0)
        in
        [left; right]
      | _ ->
        let msg = Printf.sprintf "invalid version: %s" v in
        failwith msg

    let parse = Parse.disjunction ~parse:parseNpmRange
  end

  let parse formula =
    try Ok (Parser.parse formula)
    with
    | Failure message ->
      Error (
        "Failed with message: "
          ^ message
          ^ " : "
          ^ formula
      )
    | e ->
      Error (
        "Invalid formula (pretending its any): "
        ^ formula
        ^ " "
        ^ Printexc.to_string e
      )

  let parseExn formula =
    match parse formula with
    | Ok f -> f
    | Error err -> raise (Invalid_argument err)

  let%test_module "parse" = (module struct

    let expectParsesTo v e =
      let p = parse v in
      match e, p with
      | Error _, Error _ -> true
      | Ok e, Ok p ->
        if DNF.equal p e
        then true
        else (
          Format.printf
            "@[<v 2>Failed to parse: %s@\nexpected: %a@\n     got: %a@]@\n"
            v DNF.pp e DNF.pp p;
          false
        )
      | Error _, Ok p ->
        Format.printf
          "@[<v 2>Expected to error but it parses: %s@\nas: %a@]@\n"
          v DNF.pp p;
        false
      | Ok e, Error err ->
        Format.printf
          "@[<v 2>Expected to parse but it errors: %s@\nexpected: %a@\nerror: %s@]@\n"
          v DNF.pp e err;
        false

    let cases =
      let open Constraint in
      let open Version in
      [
        "", Ok ([[ANY]]);
        " ", Ok ([[ANY]]);
        "  ", Ok ([[ANY]]);
        "*", Ok ([[ANY]]);
        "* ", Ok ([[ANY]]);
        " *", Ok ([[ANY]]);
        " * ", Ok ([[ANY]]);

        "1.x", Ok ([[GTE (make 1 0 0); LT (make 2 0 0)]]);
        "1.x.x", Ok ([[GTE (make 1 0 0); LT (make 2 0 0)]]);
        "1.1.x", Ok ([[GTE (make 1 1 0); LT (make 1 2 0)]]);

        "1", Ok ([[GTE (make 1 0 0); LT (make 2 0 0)]]);
        "1.1", Ok ([[GTE (make 1 1 0); LT (make 1 2 0)]]);

        "1.1.1", Ok ([[EQ Version.(make 1 1 1)]]);
        "=1.1.1", Ok ([[EQ Version.(make 1 1 1)]]);

        ">1", Ok ([[GT Version.(make 1 0 0)]]);
        ">1.1", Ok ([[GT Version.(make 1 1 0)]]);
        ">1.1.1", Ok ([[GT Version.(make 1 1 1)]]);

        ">1.x", Ok ([[GT Version.(make 1 0 0)]]);
        ">1.x.x", Ok ([[GT Version.(make 1 0 0)]]);
        ">1.1.x", Ok ([[GT Version.(make 1 1 0)]]);

        "<1.x", Ok ([[LT Version.(make 1 0 0)]]);
        "<1.x.x", Ok ([[LT Version.(make 1 0 0)]]);
        "<1.1.x", Ok ([[LT Version.(make 1 1 0)]]);

        "<1", Ok ([[LT Version.(make 1 0 0)]]);
        "<1.1", Ok ([[LT Version.(make 1 1 0)]]);
        "<1.1.1", Ok ([[LT Version.(make 1 1 1)]]);

        ">=1.x", Ok ([[GTE Version.(make 1 0 0)]]);
        ">=1.x.x", Ok ([[GTE Version.(make 1 0 0)]]);
        ">=1.1.x", Ok ([[GTE Version.(make 1 1 0)]]);

        ">=1", Ok ([[GTE Version.(make 1 0 0)]]);
        ">=1.1", Ok ([[GTE Version.(make 1 1 0)]]);
        ">=1.1.1", Ok ([[GTE Version.(make 1 1 1)]]);

        "<=1.x", Ok ([[LTE Version.(make 1 0 0)]]);
        "<=1.x.x", Ok ([[LTE Version.(make 1 0 0)]]);
        "<=1.1.x", Ok ([[LTE Version.(make 1 1 0)]]);

        "<=1", Ok ([[LTE Version.(make 1 0 0)]]);
        "<=1.1", Ok ([[LTE Version.(make 1 1 0)]]);
        "<=1.1.1", Ok ([[LTE Version.(make 1 1 1)]]);

        ">=1.1.1-alpha", Ok ([[GTE Version.(make ~prerelease:[W "alpha"] 1 1 1)]]);
        ">1.1.1-alpha", Ok ([[GT Version.(make ~prerelease:[W "alpha"] 1 1 1)]]);
        "<=1.1.1-alpha", Ok ([[LTE Version.(make ~prerelease:[W "alpha"] 1 1 1)]]);
        "<1.1.1-alpha", Ok ([[LT Version.(make ~prerelease:[W "alpha"] 1 1 1)]]);


        "> 1", Ok ([[GT Version.(make 1 0 0)]]);
        "> 1.1", Ok ([[GT Version.(make 1 1 0)]]);
        "> 1.1.1", Ok ([[GT Version.(make 1 1 1)]]);
        ">= 1", Ok ([[GTE Version.(make 1 0 0)]]);
        ">= 1.1", Ok ([[GTE Version.(make 1 1 0)]]);
        ">= 1.1.1", Ok ([[GTE Version.(make 1 1 1)]]);
        "< 1", Ok ([[LT Version.(make 1 0 0)]]);
        "< 1.1", Ok ([[LT Version.(make 1 1 0)]]);
        "< 1.1.1", Ok ([[LT Version.(make 1 1 1)]]);
        "<= 1", Ok ([[LTE Version.(make 1 0 0)]]);
        "<= 1.1", Ok ([[LTE Version.(make 1 1 0)]]);
        "<= 1.1.1", Ok ([[LTE Version.(make 1 1 1)]]);

        " > 1", Ok ([[GT Version.(make 1 0 0)]]);
        " > 1.1", Ok ([[GT Version.(make 1 1 0)]]);
        " > 1.1.1", Ok ([[GT Version.(make 1 1 1)]]);
        " >= 1", Ok ([[GTE Version.(make 1 0 0)]]);
        " >= 1.1", Ok ([[GTE Version.(make 1 1 0)]]);
        " >= 1.1.1", Ok ([[GTE Version.(make 1 1 1)]]);
        " < 1", Ok ([[LT Version.(make 1 0 0)]]);
        " < 1.1", Ok ([[LT Version.(make 1 1 0)]]);
        " < 1.1.1", Ok ([[LT Version.(make 1 1 1)]]);
        " <= 1", Ok ([[LTE Version.(make 1 0 0)]]);
        " <= 1.1", Ok ([[LTE Version.(make 1 1 0)]]);
        " <= 1.1.1", Ok ([[LTE Version.(make 1 1 1)]]);

        "1.1.1 || 2.2.2", Ok ([[EQ Version.(make 1 1 1)]; [EQ Version.(make 2 2 2)]]);
        "1 || 2.2.2", Ok ([
          [GTE Version.(make 1 0 0); LT Version.(make 2 0 0)];
          [EQ Version.(make 2 2 2)]
        ]);
        "1 || 2", Ok ([
          [GTE Version.(make 1 0 0); LT Version.(make 2 0 0)];
          [GTE Version.(make 2 0 0); LT Version.(make 3 0 0)];
        ]);
        "1 || 2 || 3", Ok ([
          [GTE Version.(make 1 0 0); LT Version.(make 2 0 0)];
          [GTE Version.(make 2 0 0); LT Version.(make 3 0 0)];
          [GTE Version.(make 3 0 0); LT Version.(make 4 0 0)];
        ]);
        ">1.1.1 || <2.2.2", Ok ([[GT Version.(make 1 1 1)]; [LT Version.(make 2 2 2)]]);

        ">1.1.1 <2.2.2", Ok ([[GT Version.(make 1 1 1); LT Version.(make 2 2 2)]]);
        ">1.1.1  <2.2.2", Ok ([[GT Version.(make 1 1 1); LT Version.(make 2 2 2)]]);
        ">1  <2.2.2", Ok ([[GT Version.(make 1 0 0); LT Version.(make 2 2 2)]]);
        "> 1  <2 <3", Ok ([[
          GT Version.(make 1 0 0);
          LT Version.(make 2 0 0);
          LT Version.(make 3 0 0);
        ]]);
      ]

    let%test "parsing" =
      let f passes (v, e) =
        passes && (expectParsesTo v e)
      in
      List.fold_left ~f ~init:true cases

  end)

  let%test_module "matches" = (module struct

    let expectMatches m v f =
      let pf = parseExn f in
      let pv = Version.parseExn v in
      if m = DNF.matches ~version:pv pf
      then true
      else begin
        let m = if m then "TO MATCH" else "NOT TO MATCH" in
        Format.printf "Expected %s %s %s\n" v m f;
        false
      end


    let cases = [
      true, "1.0.0", "1.0.0";
      false, "1.0.1", "1.0.0";

      true, "1.0.0", ">=1.0.0";
      true, "1.0.0", "<=1.0.0";

      true, "0.9.0", "<=1.0.0";
      true, "0.9.0", "<1.0.0";
      false, "1.1.0", "<=1.0.0";
      false, "1.1.0", "<1.0.0";

      true, "1.1.0", ">=1.0.0";
      true, "1.1.0", ">1.0.0";
      false, "0.9.0", ">=1.0.0";
      false, "1.0.0", ">1.0.0";

      true, "1.0.0", "1.0.0 - 1.1.0";
      true, "1.1.0", "1.0.0 - 1.1.0";
      false, "0.9.0", "1.0.0 - 1.1.0";
      false, "1.2.0", "1.0.0 - 1.1.0";

      (* tilda *)
      true, "1.0.0", "~1.0.0";
      false, "2.0.0", "~1.0.0";
      false, "0.9.0", "~1.0.0";
      false, "1.1.0", "~1.0.0";
      true, "1.0.1", "~1.0.0";

      true, "0.3.0", "~0.3.0";
      false, "0.4.0", "~0.3.0";
      false, "0.2.0", "~0.3.0";
      true, "0.3.1", "~0.3.0";

      (* caret *)
      true, "1.0.0", "^1.0.0";
      false, "2.0.0", "^1.0.0";
      false, "0.9.0", "^1.0.0";
      true, "1.1.0", "^1.0.0";
      true, "1.0.1", "^1.0.0";

      true, "0.3.0", "^0.3.0";
      false, "0.4.0", "^0.3.0";
      false, "0.2.0", "^0.3.0";
      true, "0.3.1", "^0.3.0";

      (* prereleases *)
      true, "1.0.0-alpha", "1.0.0-alpha";
      false, "1.0.0-alpha", ">1.0.0";
      false, "1.0.0-alpha", ">=1.0.0";
      false, "1.0.0-alpha", "<1.0.0";
      false, "1.0.0-alpha", "<=1.0.0";

      true, "1.0.0-alpha", ">=1.0.0-alpha";
      true, "1.0.0-alpha", ">=1.0.0-alpha < 2.0.0";
      true, "1.0.0-alpha.2", ">1.0.0-alpha.1 < 2.0.0";
      true, "1.0.0-alpha", ">0.1.0 <=1.0.0-alpha";
      true, "1.0.0-alpha.1", ">0.1.0 <1.0.0-alpha.2";
      true, "1.0.0-alpha", "<=1.0.0-alpha";

      true, "1.0.0-alpha.2", ">=1.0.0-alpha.1";
      true, "1.0.0-alpha.2", ">1.0.0-alpha.1";
      true, "1.0.0-alpha.1", "<=1.0.0-alpha.2";
      true, "1.0.0-alpha.1", "<1.0.0-alpha.2";

      false, "2.0.0-alpha", ">=1.0.0 < 3.0.0";
      ]

    let%test "parsing" =
      let f passes (m, v, f) =
        (expectMatches m v f) && passes
      in
      List.fold_left ~f ~init:true cases

  end)
end
