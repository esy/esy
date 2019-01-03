type t = string

let withoutScope name =
  match Astring.String.cut ~sep:"/" name with
  | None -> name
  | Some (_scope, name) -> name

