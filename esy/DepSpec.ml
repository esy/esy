module Solution = EsyInstall.Solution
module PackageId = EsyInstall.PackageId

module Id = struct
  type t =
    | Self
    | Root
    [@@deriving ord]

  let pp fmt = function
    | Self -> Fmt.unit "self" fmt ()
    | Root -> Fmt.unit "root" fmt ()
end

include EsySolve.DepSpec.Make(Id)

let root = Id.Root
let self = Id.Self

let resolve solution self id =
  match id with
  | Id.Root -> (Solution.root solution).id
  | Id.Self -> self

let eval solution self depspec =
  let resolve id = resolve solution self id in
  let rec eval' expr =
    match expr with
    | Package id -> PackageId.Set.singleton (resolve id)
    | Dependencies id ->
      let pkg = Solution.getExn (resolve id) solution in
      pkg.dependencies
    | DevDependencies id ->
      let pkg = Solution.getExn (resolve id) solution in
      pkg.devDependencies
    | Union (a, b) -> PackageId.Set.union (eval' a) (eval' b)
  in
  eval' depspec
