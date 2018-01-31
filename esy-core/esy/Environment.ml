open Std

type t = binding list

and binding = {
  name : string;
  value : bindingValue;
  origin : Package.t option;
} [@@deriving show]

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

let renderStringWithConfig (cfg : Config.t) value =
  let lookup = function
  | "store" -> Some (Path.to_string cfg.storePath)
  | "localStore" -> Some (Path.to_string cfg.localStorePath)
  | "sandbox" -> Some (Path.to_string cfg.sandboxPath)
  | _ -> None
  in
  Run.liftOfBosError (EsyBuildPackage.PathSyntax.render lookup value)

(**
 * Render environment to a string.
 *)
let renderToShellSource
    ?(header="# Environment")
    (cfg : Config.t)
    (bindings : binding list) =
  let open Run.Syntax in
  let escapeDoubleQuote value =
    let re = Str.regexp "\"" in
    Str.global_replace re "\\\"" value
  in
  let escapeSingleQuote value =
    let re = Str.regexp "'" in
    Str.global_replace re "''" value
  in
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
      let%bind value = renderStringWithConfig cfg value in
      Ok (value |> escapeDoubleQuote |> Printf.sprintf "export %s=\"%s\"" name)
    | ExpandedValue value ->
      Ok (value |> escapeSingleQuote |> Printf.sprintf "export %s=\'%s\'" name)
    in
    Ok (line::lines, origin)
  in
  let%bind lines, _ = Run.foldLeft ~f ~init:([], None) bindings in
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
  |> List.filter filterFunctions

module Value = struct

  (*
   * Environment with values with no references to other environment variables.
   *)
  type t = string Astring.String.map

  module M = Astring.String.Map

  let find = M.find_opt

  let ofBindings ?(init : t = M.empty) (bindings : binding list) =
    let open Run.Syntax in
    let f env binding =
      let scope name = M.find name env in
      match binding.value with
      | Value value ->
        let%bind value = ShellParamExpansion.render ~scope value in
        Ok (M.add binding.name value env)
      | ExpandedValue value ->
        Ok (M.add binding.name value env)
    in
    Result.listFoldLeft ~f ~init bindings

  let bindToConfig cfg env =
    let f k v = function
      | Ok env ->
        let open Run.Syntax in
        let%bind v = renderStringWithConfig cfg v in
        Ok (M.add k v env)
      | err -> err
    in
    M.fold f env (Ok M.empty)

  let to_yojson env =
    let f k v items = (k, `String v)::items in
    let items = M.fold f env [] in
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

end = struct

  type t = (Value.t * binding list)

  let bindings (_, bindings) = bindings
  let value (value, _) = value

  let ofBindings bindings =
    let open Run.Syntax in
    let%bind value = Value.ofBindings bindings in
    Ok (value, bindings)
end

module PathLike = struct

  let make (name : string) (value : string list) =
    let sep = match System.host, name with
      | System.Cygwin, "OCAMLPATH" -> ";"
      | _ -> ":"
    in
    value |> String.concat sep

end
