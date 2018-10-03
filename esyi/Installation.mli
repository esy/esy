module Package : sig
  type t = {
    id : Solution.Id.t;
    name : string;
    version : Version.t;
    source: source;
    opam : Solution.Record.Opam.t option;
    overrides : Package.Overrides.t;
    dependencies: Solution.Id.t list;
  }

  and source =
    | Link of {
        path : Path.t;
        manifest : ManifestSpec.Filename.t option;
      }
    | Install of {
        path : Path.t;
      }

  include S.JSONABLE with type t := t
  include S.COMPARABLE with type t := t
end

include Graph.GRAPH
  with
    type node = Package.t
    and type id = Solution.Id.t
