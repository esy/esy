[@deriving (to_yojson, of_yojson({strict: false}))]
type t = {pnp: [@default true] bool};

let empty = {pnp: true};
