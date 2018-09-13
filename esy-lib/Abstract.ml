module type STRING = sig
  type t
  type ctx

  val v : string -> t
  val render : ctx -> t -> string

  include S.PRINTABLE with type t := t
  include S.COMPARABLE with type t := t
  include S.JSONABLE with type t := t
end

module type PATH = sig
  type t
  type ctx

  val v : string -> t
  val (/) : t -> string -> t

  include S.PRINTABLE with type t := t
  include S.COMPARABLE with type t := t
  include S.JSONABLE with type t := t

  val ofPath : ctx -> Path.t -> t
  val toPath : ctx -> t -> Path.t
end

module type STRING_CORE = sig
  type ctx
  val render : ctx -> string -> string
end

module String = struct
  module Make (Core : STRING_CORE) : STRING with type ctx = Core.ctx = struct
    type t = string
    type ctx = Core.ctx

    let v v = v
    let render = Core.render

    let show v = v
    let pp = Fmt.string

    let compare = String.compare
    let equal = String.equal

    let of_yojson = Json.Parse.string
    let to_yojson v = `String v
  end
end
