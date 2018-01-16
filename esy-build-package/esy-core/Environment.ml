module StringMap = Map.Make(String)

type t = binding list

and binding = {
  name : string;
  value : string;
  origin : Package.t option;
}

module Normalized = struct

  (*
   * Environment with values with no references to other environment variables.
   *)
  type t = string StringMap.t

  let ofEnvironment ?(init=StringMap.empty) env =
    let f env binding =
      Ok env
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
