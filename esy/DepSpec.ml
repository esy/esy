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

include EsyInstall.DepSpec.Make(Id)

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
