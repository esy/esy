module StringMap = Map.Make(String)

type t =
  binding list
  [@@deriving show]

and binding = {
    name : string;
    value : string;
    origin : Package.t option;
  }
  [@@deriving show]

type env = t

(**
 * Render environment to a string.
 *)
let renderToShellSource
    ?(header="# Environment")
    (cfg : Config.t)
    (env : t) =
  let open Run.Syntax in
  let emptyLines = function
    | [] -> true
    | _ -> false
  in
    let lookup = function
    | "store" -> Some (Path.to_string cfg.storePath)
    | "localStore" -> Some (Path.to_string cfg.localStorePath)
    | "sandbox" -> Some (Path.to_string cfg.sandboxPath)
    | _ -> None
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
    let%bind value = Run.liftOfBosError (EsyLib.PathSyntax.render lookup value) in
    let line = Printf.sprintf "export %s=\"%s\"" name value in
    Ok (line::lines, origin)
  in
  let%bind lines, _ = Run.foldLeft ~f ~init:([], None) env in
  return (header ^ "\n" ^ (lines |> List.rev |> String.concat "\n"))


module Normalized = struct

  (*
   * Environment with values with no references to other environment variables.
   *)
  type t = string StringMap.t

  let find name env =
    try Some (StringMap.find name env)
    with Not_found -> None

  let ofEnvironment ?(init : t = StringMap.empty) (env : env) =
    let f env binding =
      let scope name =
        try Some (StringMap.find name env)
        with Not_found -> None
      in
      match ShellParamExpansion.render ~scope binding.value with
      | Ok value -> Ok (StringMap.add binding.name value env)
      | Error err -> Error err
    in
    EsyLib.Result.listFoldLeft ~f ~init env

  let to_yojson env =
    let f k v items = (k, `String v)::items in
    let items = StringMap.fold f env [] in
    `Assoc items

end

let normalize = Normalized.ofEnvironment

module PathLike = struct

  let make (name : string) (value : string list) =
    let sep = match System.host, name with
      | System.Cygwin, "OCAMLPATH" -> ";"
      | _ -> ":"
    in
    value |> String.concat sep

end
