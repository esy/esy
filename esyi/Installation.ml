module Package = struct
  type t = {
    id : Solution.Id.t;
    name : string;
    version : Version.t;
    source : source;
    opam : Solution.Record.Opam.t option;
    overrides : Package.Overrides.t;
    dependencies: Solution.Id.t list;
  } [@@deriving yojson]

  and source =
    | Link of {
        path : Path.t;
        manifest : ManifestSpec.Filename.t option;
      }
    | Install of {
        path : Path.t;
      }

  let compare a b = Solution.Id.compare a.id b.id
end

include Graph.Make(struct
  include Package

  let id pkg = pkg.id

  module Id = Solution.Id
end)
