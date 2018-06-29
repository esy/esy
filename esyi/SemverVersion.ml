module MakeFormula = Version.Formula.Make

module Version = struct
  type t = {
    major : int;
    minor : int;
    patch : int;
    release : string option;
  } [@@deriving (eq, yojson)]

  let toString { major; minor; patch; release } =
    let release = match release with | Some v -> v | None -> "" in
    Printf.sprintf "%i.%i.%i%s" major minor patch release

  let pp fmt v =
    let v = toString v in
    Fmt.string fmt v

  let show = toString

  let isint v =
    try ignore (int_of_string v); true
    with | _ -> false

  let getRest parts =
    match parts = [] with
    | true -> None
    | false -> Some (String.concat "." parts)

  let parse version =
    let parts = String.split_on_char '.' version in
    match parts with
    | major::minor::patch::rest when isint major && isint minor && isint patch ->
      Ok {
        major = int_of_string major;
        minor = int_of_string minor;
        patch = int_of_string patch;
        release = (getRest rest)
      }
    | major::minor::rest when isint major && isint minor ->
      Ok {
        major = int_of_string major;
        minor = int_of_string minor;
        patch = 0;
        release = getRest rest
      }
    | major::rest when isint major ->
      Ok {
        major = int_of_string major;
        minor = 0;
        patch = 0;
        release = getRest rest
      }
    | rest ->
      Ok {
        major = 0;
        minor = 0;
        patch = 0;
        release = getRest rest;
      }

  let parseExn v =
    match parse v with
    | Ok v -> v
    | Error err -> raise (Invalid_argument err)

  let after a prefix =
    let al = String.length a in
    let pl = String.length prefix in
    if al > pl && (String.sub a 0 pl) = prefix
    then Some (String.sub a pl (al - pl))
    else None

  let compareRelease a b =
    match a, b with
    | Some a, Some b -> begin
      match after a "-beta", after b "-beta" with
      | Some a, Some b -> begin
        try int_of_string a - int_of_string b
        with | _ -> compare a b
        end
      | _ -> begin
        match after a "-alpha", after b "-alpha" with
        | Some a, Some b -> begin
          try int_of_string a - int_of_string b
          with | _ -> compare a b
          end
        | _ -> begin
          try int_of_string a - int_of_string b
          with | _ -> compare a b
          end
      end
    end
    | _ -> compare a b

  let compare a b =
    match a.major <> b.major with
    | true -> a.major - b.major
    | false -> begin
      match a.minor <> b.minor with
        | true -> a.minor - b.minor
        | false -> begin
          match a.patch <> b.patch with
          | true -> a.patch - b.patch
          | false -> compareRelease a.release b.release
        end
    end
end

module Formula = struct
  include MakeFormula(Version)

  let any: DNF.t = OR [AND [Constraint.ANY]]

  module Parser = struct
      type partial = [
        | `Major of int
        | `Minor of int * int
        | `Patch of int * int * int
        | `Qualified of int * int * int * string
      ]

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

      let exactPartial partial =
        match partial with
        | `AllStar -> failwith "* cannot be compared"
        | `MajorStar num ->
          { Version.major = num; minor = 0; patch = 0; release = None }
        | `MinorStar (m, i) ->
          { Version.major = m; minor = i; patch = 0; release = None }
        | `Major (m, q) ->
          { Version.major = m; minor = 0; patch = 0; release = q }
        | `Minor (m, i, q) ->
          { Version.major = m; minor = i; patch = 0; release = q }
        | `Patch (m, i, p, q) ->
          { Version.major = m; minor = i; patch = p; release = q }
        | `Raw text ->
          { Version.major = 0; minor = 0; patch = 0; release = Some text }

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
              {|^\([0-9]+\)\(\.\([0-9]+\)\(\.\([0-9]+\)\)?\)?\(\([-+~][a-z0-9\.]+\)\)?|}
          in begin
          match Str.search_forward rx version 0 with
            | exception Not_found -> `Raw version
            | _ ->
              let major = int_of_string (Str.matched_group 1 version) in
              let qual =
                match Str.matched_group 7 version with
                | exception Not_found ->
                  let last = Str.match_end () in
                  if last < String.length version
                  then Some (sliceToEnd version last)
                  else None
                | text -> Some text
              in begin
              match Str.matched_group 3 version with
              | exception Not_found -> `Major (major, qual)
              | minor ->
                let minor = int_of_string minor in begin
                match Str.matched_group 5 version with
                  | exception Not_found -> `Minor (major, minor, qual)
                  | patch -> `Patch (major, minor, (int_of_string patch), qual)
                end
              end
          end

      let parsePrimitive item =
        match item.[0] with
        | '=' ->
          Constraint.EQ (parsePartial (sliceToEnd item 1) |> exactPartial)
        | '>' -> begin
          match item.[1] with
          | '=' ->
            Constraint.GTE (parsePartial (sliceToEnd item 2) |> exactPartial)
          | _ ->
            Constraint.GT (parsePartial (sliceToEnd item 1) |> exactPartial)
          end
        | '<' -> begin
          match item.[1] with
          | '=' ->
            Constraint.LTE (parsePartial (sliceToEnd item 2) |> exactPartial)
          | _ ->
            Constraint.LT (parsePartial (sliceToEnd item 1) |> exactPartial)
          end
        | _ ->
            failwith (("Bad primitive")
              [@reason.raw_literal "Bad primitive"])

      let parseSimple item =
        match item.[0] with
        | '~' -> begin
          match parsePartial (sliceToEnd item 1) with
          | `Major (num, q) ->
            AND [
              Constraint.GTE { major = num; minor = 0; patch = 0; release = q };
              Constraint.LT { major = num + 1; minor = 0; patch = 0; release = None };
            ]
          | `Minor (m, i, q) ->
            AND [
              Constraint.GTE { major = m; minor = i; patch = 0; release = q };
              Constraint.LT { major = m; minor = i + 1; patch = 0; release = None };
            ]
          | `Patch (m, i, p, q) ->
            AND [
              Constraint.GTE { major = m; minor = i; patch = p; release = q };
              Constraint.LT { major = m; minor = i + 1; patch = 0; release = None };
            ]
          | `AllStar ->
            failwith "* cannot be tilded"
          | `MajorStar num ->
            AND [
              Constraint.GTE { major = num; minor = 0; patch = 0; release = None };
              Constraint.LT { major = num + 1; minor = 0; patch = 0; release = None };
            ]
          | `MinorStar (m, i) ->
            AND [
              Constraint.GTE { major = m; minor = i; patch = 0; release = None };
              Constraint.LT { major = m; minor = i + 1; patch = 0; release = None };
            ]
          | `Raw _ ->
            failwith "Bad tilde"
          end

        | '^' -> begin
          match parsePartial (sliceToEnd item 1) with
          | `Major (num, q) ->
            AND [
              GTE { major = num; minor = 0; patch = 0; release = q };
              LT { major = num + 1; minor = 0; patch = 0; release = None };
            ]
          | `Minor (0, i, q) ->
            AND [
              GTE { major = 0; minor = i; patch = 0; release = q };
              LT { major = 0; minor = i + 1; patch = 0; release = None };
            ]
          | `Minor (m, i, q) ->
            AND [
              Constraint.GTE { major = m; minor = i; patch = 0; release = q };
              Constraint.LT { major = m + 1; minor = 0; patch = 0; release = None };
            ]
          | `Patch (0, 0, p, q) ->
            AND [
              Constraint.GTE { major = 0; minor = 0; patch = p; release = q };
              Constraint.LT { major = 0; minor = 0; patch = p + 1; release = None };
            ]
          | `Patch (0, i, p, q) ->
            AND [
              GTE { major = 0; minor = i; patch = p; release = q };
              LT { major = 0; minor = i + 1; patch = 0; release = None };
            ]
          | `Patch (m, i, p, q) ->
            AND [
              Constraint.GTE { major = m; minor = i; patch = p; release = q };
              Constraint.LT { major = m + 1; minor = 0; patch = 0; release = None };
            ]
          | `AllStar -> failwith "* cannot be careted"
          | `MajorStar num ->
            AND [
              Constraint.GTE { major = num; minor = 0; patch = 0; release = None };
              Constraint.LT { major = num + 1; minor = 0; patch = 0; release = None };
            ]
          | `MinorStar (m, i) ->
            AND [
              Constraint.GTE { major = m; minor = i; patch = 0; release = None };
              Constraint.LT { major = m + 1; minor = i; patch = 0; release = None };
            ]
          | `Raw _ -> failwith "Bad tilde"
        end

        | '>'|'<'|'=' -> AND [parsePrimitive item]

        | _ ->
          begin match parsePartial item with
            | `AllStar -> AND [ANY]
            | `Major (m, Some x) ->
              AND [
                EQ { major = m; minor = 0; patch = 0; release = Some x; };
              ]
            | `Major (m, None)
            | `MajorStar m ->
              AND [
                GTE { major = m; minor = 0; patch = 0; release = None };
                LT { major = m + 1; minor = 0; patch = 0; release = None };
              ]
            | `Minor (m, i, Some x) ->
              AND [
                EQ { major = m; minor = i; patch = 0; release = Some x; };
              ]
            | `Minor (m, i, None)
            |`MinorStar (m, i) ->
              AND [
                GTE { major = m; minor = i; patch = 0; release = None };
                LT { major = m; minor = i + 1; patch = 0; release = None };
              ]
            | `Patch (m, i, p, q) ->
              AND [
                EQ { major = m; minor = i; patch = p; release = q };
              ]
            | `Raw text ->
              AND [
                EQ { major = 0; minor = 0; patch = 0; release = Some text };
              ]
          end

      let parseNpmRange simple =
        let items = Str.split (Str.regexp " +- +") simple in
        match items with
        | item::[] -> parseSimple item
        | left::right::[] ->
          let left = Constraint.GTE (parsePartial left |> exactPartial) in
          let right =
            match parsePartial right with
            | `AllStar -> Constraint.ANY
            | `Major (m, _)
            | `MajorStar m ->
              Constraint.LT {
                major = (m + 1);
                minor = 0;
                patch = 0;
                release = None
              }
            | `Minor (m, i, _)
            | `MinorStar (m, i) ->
              Constraint.LT {
                major = m;
                minor = (i + 1);
                patch = 0;
                release = None
              }
            | `Patch (m, i, p, q) ->
              Constraint.LTE {
                major = m;
                minor = i;
                patch = p;
                release = q;
              }
            | `Raw text ->
              Constraint.LT {
                major = 0;
                minor = 0;
                patch = 0;
                release = Some text;
              }
          in
          AND [left; right]
        | _ -> failwith "Invalid range"

      let parse = Parse.disjunction ~parse:parseNpmRange
    end

    let parse version =
      try Parser.parse version
      with
      | Failure message ->
        print_endline (
          "Failed with message: "
            ^ message
            ^ " : "
            ^ version
        );
        any
      | e ->
        print_endline (
          "Invalid version! pretending its any: "
          ^ version
          ^ " "
          ^ Printexc.to_string e
        );
        any
  end
