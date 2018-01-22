module StringMap = Map.Make(String)

type binding = {
    name : string;
    value : string;
    origin : Package.t option;
  }
  [@@deriving show]

let renderStringWithConfig (cfg : Config.t) value =
  let lookup = function
  | "store" -> Some (Path.to_string cfg.storePath)
  | "localStore" -> Some (Path.to_string cfg.localStorePath)
  | "sandbox" -> Some (Path.to_string cfg.sandboxPath)
  | _ -> None
  in
  Run.liftOfBosError (EsyLib.PathSyntax.render lookup value)

(**
 * Render environment to a string.
 *)
let renderToShellSource
    ?(header="# Environment")
    (cfg : Config.t)
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
    let%bind value = renderStringWithConfig cfg value in
    let line = Printf.sprintf "export %s=\"%s\"" name value in
    Ok (line::lines, origin)
  in
  let%bind lines, _ = Run.foldLeft ~f ~init:([], None) bindings in
  return (header ^ "\n" ^ (lines |> List.rev |> String.concat "\n"))

module Value = struct

  (*
   * Environment with values with no references to other environment variables.
   *)
  type t = string StringMap.t

  let find name env =
    try Some (StringMap.find name env)
    with Not_found -> None

  let ofBindings ?(init : t = StringMap.empty) (bindings : binding list) =
    let f env binding =
      let scope name =
        try Some (StringMap.find name env)
        with Not_found -> None
      in
      match ShellParamExpansion.render ~scope binding.value with
      | Ok value -> Ok (StringMap.add binding.name value env)
      | Error err -> Error err
    in
    EsyLib.Result.listFoldLeft ~f ~init bindings

  let bindToConfig cfg env =
    let f k v = function
      | Ok env ->
        let open Run.Syntax in
        let%bind v = renderStringWithConfig cfg v in
        Ok (StringMap.add k v env)
      | err -> err
    in
    StringMap.fold f env (Ok StringMap.empty)

  let to_yojson env =
    let f k v items = (k, `String v)::items in
    let items = StringMap.fold f env [] in
    `Assoc items

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
