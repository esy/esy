type t = binding list [@@deriving (show, eq, ord)]

and binding = {
  name : string;
  value : bindingValue;
  origin : Package.t option
    [@printer fun fmt origin -> Fmt.(option string) fmt (Option.map ~f:(fun o -> o.Package.id) origin)];
} [@@deriving (show, eq, ord)]

(* TODO: Expand this variant to include
 *
 *   - Path of string
 *   - PathConcat of * string list
 *
 * And defer its expansion till the `esy-build-package` invocation.
 *)
and bindingValue =
  | Value of string
  | ExpandedValue of string

let renderPath ~storePath ~localStorePath ~sandboxPath value =
  let lookup = function
  | "store" -> Some (Path.to_string storePath)
  | "localStore" -> Some (Path.to_string localStorePath)
  | "sandbox" -> Some (Path.to_string sandboxPath)
  | _ -> None
  in
  Run.ofBosError (EsyBuildPackage.PathSyntax.render lookup value)

let bindingListPp = pp
let bindingListEq = equal
let bindingListCompare = compare

let bindToConfig (cfg : Config.t) (env : t) =
  let open Run.Syntax in
  let render v = 
    renderPath
      ~storePath:cfg.storePath
      ~localStorePath:cfg.localStorePath
      ~sandboxPath:cfg.sandboxPath
      v
  in
  let f binding =
    let%bind value =
      match binding.value with
      | Value v -> let%bind v = render v in return (Value v)
      | ExpandedValue v -> let%bind v = render v in return (ExpandedValue v)
    in return {binding with value}
  in
  Result.List.map ~f env

let escapeDoubleQuote value =
  let re = Str.regexp "\"" in
  Str.global_replace re "\\\"" value

let escapeSingleQuote value =
  let re = Str.regexp "'" in
  Str.global_replace re "''" value

(**
 * Render environment to a string.
 *)
let renderToShellSource
    ?(header="# Environment")
    ~storePath
    ~localStorePath
    ~sandboxPath
    (bindings : binding list) =
  let open Run.Syntax in
  let emptyLines = function
    | [] -> true
    | _ -> false
  in
  let f (lines, prevOrigin) ({ name; value; origin } : binding) =
    let lines = if prevOrigin <> origin || emptyLines lines then
      let header = match origin with
      | Some origin -> Printf.sprintf "\n#\n# Package %s@%s\n#" origin.name origin.version
      | None -> "\n#\n# Built-in\n#"
      in header::lines
    else
      lines
    in
    let%bind line = match value with
    | Value value ->
      let%bind value = renderPath
        ~storePath
        ~localStorePath
        ~sandboxPath
        value
      in
      Ok (value |> escapeDoubleQuote |> Printf.sprintf "export %s=\"%s\"" name)
    | ExpandedValue value ->
      Ok (value |> escapeSingleQuote |> Printf.sprintf "export %s=\'%s\'" name)
    in
    Ok (line::lines, origin)
  in
  let%bind lines, _ = Run.List.foldLeft ~f ~init:([], None) bindings in
  return (header ^ "\n" ^ (lines |> List.rev |> String.concat "\n"))

let current =
  let parseEnv item =
    let idx = String.index item '=' in
    let name = String.sub item 0 idx in
    let value = String.sub item (idx + 1) (String.length item - idx - 1) in
    {name; value = ExpandedValue value; origin = None;}
  in
  (* Filter bash function which are being exported in env *)
  let filterFunctions {name; _} =
    let starting = "BASH_FUNC_" in
    let ending = "%%" in
    not (
      String.length name > String.length starting
      && Str.first_chars name (String.length starting) = starting
      && Str.last_chars name (String.length ending) = ending
    )
  in
  Unix.environment ()
  |> Array.map parseEnv
  |> Array.to_list
  |> List.filter ~f:filterFunctions

let ofSandboxEnv =
  let toEnvVar (Manifest.Env. {name; value}) = {
    name;
    value = Value value;
    origin = None;
  } in
  List.map ~f:toEnvVar

module Value = struct

  (*
   * Environment with values with no references to other environment variables.
   *)
  type t = string Astring.String.Map.t

  let pp = Astring.String.Map.pp

  let find = StringMap.find_opt

  let ofBindings ?(init : t = StringMap.empty) (bindings : binding list) =
    let open Run.Syntax in
    let f env binding =
      let scope name = StringMap.find name env in
      match binding.value with
      | Value value ->
        let%bind value = ShellParamExpansion.render ~scope value in
        Ok (StringMap.add binding.name value env)
      | ExpandedValue value ->
        Ok (StringMap.add binding.name value env)
    in
    Result.List.foldLeft ~f ~init bindings

  let bindToConfig (cfg : Config.t) env =
    let f k value = function
      | Ok env ->
        let open Run.Syntax in
        let%bind v = renderPath
          ~storePath:cfg.storePath
          ~localStorePath:cfg.localStorePath
          ~sandboxPath:cfg.sandboxPath
          value
        in
        Ok (StringMap.add k v env)
      | err -> err
    in
    StringMap.fold f env (Ok StringMap.empty)

  let to_yojson env =
    let f k v items = (k, `String v)::items in
    let items = StringMap.fold f env [] in
    `Assoc items

  let current =
    match ofBindings current with
    | Ok env -> env
    | Error err ->
      let msg = Run.formatError err in
      failwith msg

end

(**
 * A closed environment (which doesn't have references outside of own values).
 *)
module Closed : sig

  type t

  val bindings : t -> binding list
  val value : t -> Value.t

  val ofBindings : binding list -> t Run.t

  val pp : Format.formatter -> t -> unit
  val equal : t -> t -> bool
  val compare : t -> t -> int

end = struct

  type t = (Value.t * binding list)

  let pp fmt (_, bindings) = bindingListPp fmt bindings
  let equal (_, a) (_, b) = bindingListEq a b
  let compare (_, a) (_, b) = bindingListCompare a b

  let bindings (_, bindings) = bindings
  let value (value, _) = value

  let ofBindings bindings =
    let open Run.Syntax in
    let%bind value = Value.ofBindings bindings in
    Ok (value, bindings)
end
