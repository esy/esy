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
