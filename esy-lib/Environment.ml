module Binding = struct

  type 'v t = {
    name : string;
    value : 'v value;
    origin : string option;
  }
  [@@deriving ord]

  and 'v value =
    | Value of 'v
    | ExpandedValue of 'v
    | Prefix of 'v
    | Suffix of 'v
end

module type S = sig
  type ctx
  type value

  type t = value StringMap.t
  type env = t

  val empty : t
  val find : string -> t -> value option
  val add : string -> value -> t -> t
  val map : f:(string -> string) -> t -> t

  val render : ctx -> t -> string StringMap.t

  include S.COMPARABLE with type t := t
  include S.JSONABLE with type t := t

  module Bindings : sig

    type t =
      value Binding.t list

    val value : ?origin:string -> string -> value -> value Binding.t
    val prefixValue : ?origin:string -> string -> value -> value Binding.t
    val suffixValue : ?origin:string -> string -> value -> value Binding.t

    val empty : t
    val render : ctx -> t -> string Binding.t list
    val eval : ?platform : System.Platform.t -> ?init : env -> t -> (env, string) result
    val map : f:(string -> string) -> t -> t

    val current : t

    include S.COMPARABLE with type t := t
  end
end

module Make (V : Abstract.STRING) : sig
  include S
    with type value = V.t
    and type ctx = V.ctx
end = struct

  type value = V.t
  type ctx = V.ctx

  type t =
    V.t StringMap.t
    [@@deriving ord, yojson]

  type env = t

  let add = StringMap.add
  let empty = StringMap.empty
  let find = StringMap.find
  let map ~f env =
    let f value = value |> V.show |> f |> V.v in
    StringMap.map f env

  let render ctx env =
    let f name value map =
      let value = V.render ctx value in
      StringMap.add name value map
    in
    StringMap.fold f env StringMap.empty

  module Bindings = struct
    type t =
      V.t Binding.t list
      [@@deriving ord]

    let empty = []
    let value ?origin name value = {Binding. name; value = Value value; origin}

    let prefixValue ?origin name value =
      let value = Binding.Prefix value in
      {Binding.name; value; origin;}

    let suffixValue ?origin name value =
      let value = Binding.Suffix value in
      {Binding.name; value; origin;}

    let map ~f bindings =
      let f binding =
        let value =
          match binding.Binding.value with
          | Binding.Value value ->
            Binding.Value (value |> V.show |> f |> V.v)
          | Binding.ExpandedValue value ->
            Binding.ExpandedValue (value |> V.show |> f |> V.v)
          | Binding.Prefix value ->
            Binding.Prefix (value |> V.show |> f |> V.v)
          | Binding.Suffix value ->
            Binding.Suffix (value |> V.show |> f |> V.v)
        in
        {binding with value}
      in
      List.map ~f bindings

    let render ctx bindings =
      let f {Binding. name; value; origin} =
        let value =
          match value with
          | Binding.ExpandedValue value -> Binding.ExpandedValue (V.render ctx value)
          | Binding.Value value -> Binding.Value (V.render ctx value)
          | Binding.Prefix value -> Binding.Prefix (V.render ctx value)
          | Binding.Suffix value -> Binding.Suffix (V.render ctx value)
        in
        {Binding. name; value; origin}
      in
      List.map ~f bindings

    let eval ?(platform=System.Platform.host) ?(init=StringMap.empty) bindings =
      let open Result.Syntax in

      let f env binding =
        let scope name =
          match StringMap.find name env with
          | Some v -> Some (V.show v)
          | None -> None
        in
        match binding.Binding.value with
        | Value value ->
          let value = V.show value in
          let%bind value = EsyShellExpansion.render ~scope value in
          let value = V.v value in
          Ok (StringMap.add binding.name value env)
        | ExpandedValue value ->
          Ok (StringMap.add binding.name value env)
        | Prefix value ->
          let value = V.show value in
          let value =
            match StringMap.find binding.name env with
            | Some prevValue ->
              let sep = System.Environment.sep ~platform ~name:binding.name () in
              value ^ sep ^ (V.show prevValue)
            | None -> value
          in
          let value = V.v value in
          Ok (StringMap.add binding.name value env)
        | Suffix value ->
          let value = V.show value in
          let value =
            match StringMap.find binding.name env with
            | Some prevValue ->
              let sep = System.Environment.sep ~platform ~name:binding.name () in
              (V.show prevValue) ^ sep ^ value
            | None -> value
          in
          let value = V.v value in
          Ok (StringMap.add binding.name value env)
      in
      Result.List.foldLeft ~f ~init bindings

    let current =
      let parseEnv item =
        let idx = String.index item '=' in
        let name = String.sub item 0 idx in
        let name =
          match System.Platform.host with
          | System.Platform.Windows -> String.uppercase_ascii name
          | _ -> name
        in
        let value = String.sub item (idx + 1) (String.length item - idx - 1) in
        {Binding. name; value = ExpandedValue (V.v value); origin = None;}
      in
      (* Filter bash function which are being exported in env *)
      let filterInvalidNames {Binding. name; _} =
        let starting = "BASH_FUNC_" in
        let ending = "%%" in
        not (
          (
            String.length name > String.length starting
            && Str.first_chars name (String.length starting) = starting
            && Str.last_chars name (String.length ending) = ending
          )
          || String.contains name '.'
        )
      in
      Unix.environment ()
      |> Array.map parseEnv
      |> Array.to_list
      |> List.filter ~f:filterInvalidNames

  end
end

module V = Make(struct
  include String
  type ctx = unit
  let v v = v
  let of_yojson = Json.Decode.string
  let to_yojson v = `String v
  let show v = v
  let pp = Fmt.string
  let render () v = v
end)

include V

let escapeDoubleQuote value =
  let re = Str.regexp "\"" in
  Str.global_replace re "\\\"" value

let escapeSingleQuote value =
  let re = Str.regexp "'" in
  Str.global_replace re "''" value

let renderToShellSource
    ?(header="# Environment")
    ?(platform=System.Platform.host)
    (bindings : string Binding.t list) =
  let open Run.Syntax in
  let emptyLines = function
    | [] -> true
    | _ -> false
  in
  let f (lines, prevOrigin) {Binding. name; value; origin } =
    let lines = if prevOrigin <> origin || emptyLines lines then
      let header = match origin with
      | Some origin -> Printf.sprintf "\n#\n# %s\n#" origin
      | None -> "\n#\n# Built-in\n#"
      in header::lines
    else
      lines
    in
    let%bind line = match value with
    | Value value ->
      let value = escapeDoubleQuote value in
      Ok (Printf.sprintf "export %s=\"%s\"" name value)
    | ExpandedValue value ->
      let value = escapeSingleQuote value in
      Ok (Printf.sprintf "export %s=\'%s\'" name value)
    | Prefix value ->
      let sep = System.Environment.sep ~platform ~name () in
      let value = escapeDoubleQuote value in
      Ok (Printf.sprintf "export %s=\"%s%s$%s\"" name value sep name)
    | Suffix value ->
      let sep = System.Environment.sep ~platform ~name () in
      let value = escapeDoubleQuote value in
      Ok (Printf.sprintf "export %s=\"$%s%s%s\"" name name sep value)
    in
    Ok (line::lines, origin)
  in
  let%bind lines, _ = Run.List.foldLeft ~f ~init:([], None) bindings in
  return (header ^ "\n" ^ (lines |> List.rev |> String.concat "\n"))

let renderToList ?(platform=System.Platform.host) bindings =
  let f {Binding.name; value; origin = _} =
    let value =
      match value with
      | Binding.Value value -> value
      | Binding.ExpandedValue value -> value
      | Binding.Prefix value ->
        let sep = System.Environment.sep ~platform ~name () in
        value ^ sep ^ "$" ^ name
      | Binding.Suffix value ->
        let sep = System.Environment.sep ~platform ~name () in
        "$" ^ name ^ sep ^ value
    in
    name, value
  in
  List.map ~f bindings
