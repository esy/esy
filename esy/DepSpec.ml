open EsyPackageConfig

include DepSpecBase

let resolve solution self id =
  match id with
  | Id.Root -> (EsyInstall.Solution.root solution).id
  | Id.Self -> self

let eval solution self depspec =
  let resolve id = resolve solution self id in
  let rec eval' expr =
    match expr with
    | Package id -> PackageId.Set.singleton (resolve id)
    | Dependencies id ->
      let pkg = EsyInstall.Solution.getExn (resolve id) solution in
      pkg.dependencies
    | DevDependencies id ->
      let pkg = EsyInstall.Solution.getExn (resolve id) solution in
      pkg.devDependencies
    | Union (a, b) -> PackageId.Set.union (eval' a) (eval' b)
  in
  eval' depspec

let rec collect' solution depspec seen id =
  if PackageId.Set.mem id seen
  then seen
  else
    let f nextid seen = collect' solution depspec seen nextid in
    let seen = PackageId.Set.add id seen in
    let seen = PackageId.Set.fold f (eval solution id depspec) seen in
    seen

let collect solution depspec root =
  collect' solution depspec PackageId.Set.empty root

let parse v =
  let open Result.Syntax in
  let lexbuf = Lexing.from_string v in
  try return (DepSpecParser.start DepSpecLexer.read lexbuf) with
  | DepSpecLexer.Error msg ->
    let msg = Printf.sprintf "error parsing DEPSPEC: %s" msg in
    error msg
  | DepSpecParser.Error -> error "error parsing DEPSPEC"

let of_yojson json =
  match json with
  | `String v -> parse v
  | _ -> Result.errorf "expected string"

let to_yojson spec =
  let s = Format.asprintf "%a" pp spec in
  `String s
