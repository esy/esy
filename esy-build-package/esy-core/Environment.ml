module StringMap = Map.Make(String)

type t = binding list

and binding = {
  name : string;
  value : string;
  origin : Package.t option;
}

type env = t

(**
 * Render environment to a string.
 *)
let render (env : t) =
  let f (lines, prevOrigin) ({ name; value; origin } : binding) =
    let lines, origin = if prevOrigin <> origin then
      lines, origin
    else
      lines, origin
    in
    let value = Printf.sprintf "export %s = \"%s\"" name value in
    value::lines, origin
  in
  let lines, _ = ListLabels.fold_left ~f ~init:([], None) env in
  String.concat "\n" lines


module Normalized = struct

  (*
   * Environment with values with no references to other environment variables.
   *)
  type t = string StringMap.t

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

end

let normalize = Normalized.ofEnvironment

module PathLike = struct

  let make (name : string) (value : Path.t list) =
    let sep = match System.host, name with
      | System.Cygwin, "OCAMLPATH" -> ";"
      | _ -> ":"
    in
    value |> List.map Path.to_string |> String.concat sep

end
