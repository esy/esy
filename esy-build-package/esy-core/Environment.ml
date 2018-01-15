
type t = binding list

and binding = {
  name : string;
  value : string;
  origin : Package.t option;
}

module PathLike = struct

  let make (name : string) (value : Path.t list) =
    let sep = match System.host, name with
      | System.Cygwin, "OCAMLPATH" -> ";"
      | _ -> ":"
    in
    value |> List.map Path.to_string |> String.concat sep

end
