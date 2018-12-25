include Path

let ofPath p = (normalizeAndRemoveEmptySeg p)

let toPath base p = normalizeAndRemoveEmptySeg (base // p)

let make ~base p =
  let base = normalizeAndRemoveEmptySeg base in
  let p = normalizeAndRemoveEmptySeg p in
  if compare p base = 0
  then v "."
  else normalizeAndRemoveEmptySeg (tryRelativize ~root:base p)

let rebase ~base p = normalizeAndRemoveEmptySeg (base // p)

let render path = normalizePathSlashes (show path)

let (/) path seg = normalizeAndRemoveEmptySeg (path / seg)

let show = render
let showPretty path = Path.(normalizePathSlashes (showPretty path))

let to_yojson path = `String (render path)

let sexp_of_t path = Sexplib0.Sexp.Atom (render path)
