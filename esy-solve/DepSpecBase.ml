module Id = struct
  type t =
    | Self
    [@@deriving ord]

  let pp fmt = function
    | Self -> Fmt.unit "self" fmt ()
end

include EsyInstall.DepSpec.Make(Id)

let self = Id.Self

