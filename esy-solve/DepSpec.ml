open EsyPackageConfig
include DepSpecBase

let rec eval (manifest : InstallManifest.t) (spec : t) =
  let module D = InstallManifest.Dependencies in
  let open Run.Syntax in
  match spec with
  | Package Self -> return (D.NpmFormula NpmFormula.empty)
  | Dependencies Self -> return manifest.dependencies
  | DevDependencies Self -> return manifest.devDependencies
  | Union (a, b) ->
    let%bind adeps = eval manifest a in
    let%bind bdeps = eval manifest b in
    begin match adeps, bdeps with
    | D.NpmFormula a, D.NpmFormula b ->
      let reqs = NpmFormula.override a b in
      return (D.NpmFormula reqs)
    | D.OpamFormula a, D.OpamFormula b ->
      return (D.OpamFormula (a @ b))
    | _, _ ->
      errorf
        "incompatible dependency formulas found at %a: %a and %a"
        InstallManifest.pp manifest pp a pp b
    end

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
