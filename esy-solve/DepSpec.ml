open EsyPackageConfig


module Id = struct
  type t =
    | Self
    [@@deriving ord]

  let pp fmt = function
    | Self -> Fmt.unit "self" fmt ()
end

include EsyInstall.DepSpecAst.Make(Id)

let self = Id.Self

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

let rec toDepSpec (spec : t) =
  match spec with
  | Package Self -> EsyInstall.DepSpec.(package self)
  | Dependencies Self -> EsyInstall.DepSpec.(dependencies self)
  | DevDependencies Self -> EsyInstall.DepSpec.(devDependencies self)
  | Union (a, b) -> EsyInstall.DepSpec.(toDepSpec a + toDepSpec b)
