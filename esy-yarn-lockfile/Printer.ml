open Types

let ppStringQuotedIfNeeded fmt s =
  if String.contains s ' '
  then Fmt.(quote string) fmt s
  else Fmt.string fmt s

let ppScalar fmt (v : scalar) =
  match v with
  | Number n -> Fmt.float fmt n
  | String s -> ppStringQuotedIfNeeded fmt s
  | Boolean true -> Fmt.pf fmt "true"
  | Boolean false -> Fmt.pf fmt "false"

let rec pp fmt (v : t) =
  match v with
  | Mapping items ->
    let ppItem fmt (k, v) =
      match v with
      | Scalar scalar -> Fmt.pf fmt "%a: %a" ppStringQuotedIfNeeded k ppScalar scalar
      | Mapping _ -> Fmt.pf fmt "%s:@;<0 2>@[<v 2>%a@]" k pp v
      | Sequence _ -> Fmt.pf fmt "%s:@;<0 2>@[<v 2>%a@]" k pp v
    in
    Fmt.(vbox (list ~sep:(unit "@;") ppItem)) fmt items
  | Sequence items ->
    let ppItem fmt v =
      Fmt.pf fmt "- %a" pp v
    in
    Fmt.(vbox (list ~sep:(unit "@;") ppItem)) fmt items
  | Scalar scalar -> ppScalar fmt scalar
