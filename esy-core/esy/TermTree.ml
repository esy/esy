(**
 * Output trees on terminal
 *)

type t =
  | Node of { line : string; children : t list }


let toString (node : t) =
  let rec nodeToLines ~indent ~lines (Node { line; children }) =
    let lines =
      let indent = indent |> List.rev |> StringLabels.concat ~sep:"" in
      (indent ^ line)::lines
    in
    let indent = match indent with
    | [] -> []
    | "└── "::indent -> "    "::indent
    | _::indent -> "|   "::indent
    in
    nodeListToLines ~indent ~lines children
  and nodeListToLines ~indent ~lines = function
    | [] -> lines
    | node::[] -> nodeToLines ~indent:("└── "::indent) ~lines node
    | node::nodes ->
      let lines = nodeToLines ~indent:("├── "::indent) ~lines node in
      nodeListToLines ~indent ~lines nodes
  in
  node
  |> nodeToLines ~indent:[] ~lines:[]
  |> List.rev
  |> StringLabels.concat ~sep:"\n"
