module Command : sig
  type t =
    | Parsed of string list
    | Unparsed of string

  include S.COMPARABLE with type t := t
  include S.JSONABLE with type t := t
  include S.PRINTABLE with type t := t

end = struct

  type t =
    | Parsed of string list
    | Unparsed of string
    [@@deriving (show, eq, ord)]

  let of_yojson (json : Json.t) =
    match json with
    | `String command -> Ok (Unparsed command)
    | `List command ->
      begin match Json.Decode.(list string (`List command)) with
      | Ok args -> Ok (Parsed args)
      | Error err -> Error err
      end
    | _ -> Error "expected either a string or an array of strings"

  let to_yojson v =
    match v with
    | Parsed args -> `List (List.map ~f:(fun arg -> `String arg) args)
    | Unparsed line -> `String line
end

module CommandList : sig

  type t =
    Command.t list

  include S.COMPARABLE with type t := t
  include S.JSONABLE with type t := t
  include S.PRINTABLE with type t := t

  val empty : t
end = struct

  type t =
    Command.t list
    [@@deriving (show, eq, ord)]

  let empty = []

  let of_yojson (json : Json.t) =
    let open Result.Syntax in
    let commands =
      match json with
      | `Null -> return []
      | `List commands ->
        Json.Decode.list Command.of_yojson (`List commands)
      | `String command ->
        let%bind command = Command.of_yojson (`String command) in
        return [command]
      | _ -> Error "expected either a null, a string or an array"
    in
    match%bind commands with
    | [] -> Ok []
    | commands -> Ok commands

  let to_yojson commands =
    `List (List.map ~f:Command.to_yojson commands)
end

module rec R : sig


  module Env : sig

    type item = {
      name : string;
      value : string;
    }
    [@@deriving (show, eq, ord)]

    type t =
      item list

    include S.PRINTABLE with type t := t
    include S.COMPARABLE with type t := t

  end

  module ExportedEnv : sig

    type scope =
      | Local
      | Global
      [@@deriving (show, eq, ord)]

    type item = {
      name : string;
      value : string;
      scope : scope;
      exclusive : bool;
    }
    [@@deriving (show, eq, ord)]

    type t =
      item list

    include S.PRINTABLE with type t := t
    include S.COMPARABLE with type t := t

  end

  module Source : sig
    type t =
      | Orig of source
      | Override of {source : source; override : R.SourceOverride.t;}

    and source =
      | Archive of {
          url : string;
          checksum : Checksum.t;
        }
      | Git of {
          remote : string;
          commit : string;
          manifest : SandboxSpec.ManifestSpec.t option;
        }
      | Github of {
          user : string;
          repo : string;
          commit : string;
          manifest : SandboxSpec.ManifestSpec.t option;
        }
      | LocalPath of {
          path : Path.t;
          manifest : SandboxSpec.ManifestSpec.t option;
        }
      | LocalPathLink of {
          path : Path.t;
          manifest : SandboxSpec.ManifestSpec.t option;
        }
      | NoSource

    include S.COMPARABLE with type t := t
  end

  module SourceSpec : sig
    type t =
      | Orig of sourceSpec
      | Override of {sourceSpec : sourceSpec; override : R.SourceOverride.t;}
    and sourceSpec =
      | Archive of {
          url : string;
          checksum : Checksum.t option;
        }
      | Git of {
          remote : string;
          ref : string option;
          manifest : SandboxSpec.ManifestSpec.t option;
        }
      | Github of {
          user : string;
          repo : string;
          ref : string option;
          manifest : SandboxSpec.ManifestSpec.t option;
        }
      | LocalPath of {
          path : Path.t;
          manifest : SandboxSpec.ManifestSpec.t option;
        }
      | LocalPathLink of {
          path : Path.t;
          manifest : SandboxSpec.ManifestSpec.t option;
        }
      | NoSource

    include S.COMPARABLE with type t := t
  end

  module Version : sig
    type t =
      | Npm of SemverVersion.Version.t
      | Opam of OpamPackageVersion.Version.t
      | Source of Source.t
      [@@deriving (ord, eq)]
  end

  module VersionSpec : sig
    type t =
      | Npm of SemverVersion.Formula.DNF.t
      | NpmDistTag of string * SemverVersion.Version.t option
      | Opam of OpamPackageVersion.Formula.DNF.t
      | Source of SourceSpec.t

    include S.COMPARABLE with type t := t
  end

  module Req : sig
    type t = {
      name: string;
      spec: VersionSpec.t;
    }
    include S.COMPARABLE with type t := t
  end


  module Dependencies : sig
    type t =
      Req.t list

    include S.COMPARABLE with type t := t
  end

  module Resolutions : sig
    type t =
      Version.t StringMap.t

    include S.COMPARABLE with type t := t
  end

  module SourceOverride : sig

    type dependencyOverride =
      | Remove of string
      | Define of Req.t
      [@@deriving eq, ord]

    type envOverride =
      | Remove of string
      | Define of Env.item
      [@@deriving eq, ord]

    type exportedEnvOverride =
      | Remove of string
      | Define of ExportedEnv.item
      [@@deriving eq, ord]

    type t = {
      name : string option;
      version : string option;
      build : CommandList.t option;
      install : CommandList.t option;
      (* exportedEnv : ExportedEnv.t option; *)
      (* exportedEnvOverride : exportedEnvOverride list option; *)
      (* buildEnv : Env.t option; *)
      (* buildEnvOverride : envOverride list option; *)
      (* sandboxEnv : ExportedEnv.t option; *)
      (* sandboxEnvOverride : envOverride list option; *)
      (* dependencies : Dependencies.t option; *)
      (* dependenciesOverride : dependencyOverride list option; *)
      (* resolutions : Resolutions.t option; *)
    }
    [@@deriving eq, ord]
  end

end = struct

  module Env = struct

    type item = {
      name : string;
      value : string;
    }
    [@@deriving (show, eq, ord)]

    type t =
      item list
      [@@deriving (show, eq, ord)]
  end

  module ExportedEnv = struct

    type scope =
      | Local
      | Global
      [@@deriving (show, eq, ord)]

    type item = {
      name : string;
      value : string;
      scope : scope;
      exclusive : bool;
    }
    [@@deriving (show, eq, ord)]

    type t =
      item list
      [@@deriving (show, eq, ord)]

  end

  module Source = struct
    type t =
      | Orig of source
      | Override of {source : source; override : R.SourceOverride.t;}

    and source =
      | Archive of {
          url : string;
          checksum : Checksum.t;
        }
      | Git of {
          remote : string;
          commit : string;
          manifest : SandboxSpec.ManifestSpec.t option;
        }
      | Github of {
          user : string;
          repo : string;
          commit : string;
          manifest : SandboxSpec.ManifestSpec.t option;
        }
      | LocalPath of {
          path : Path.t;
          manifest : SandboxSpec.ManifestSpec.t option;
        }
      | LocalPathLink of {
          path : Path.t;
          manifest : SandboxSpec.ManifestSpec.t option;
        }
      | NoSource
      [@@deriving ord, eq]
  end

  module SourceSpec = struct
    type t =
      | Orig of sourceSpec
      | Override of {sourceSpec : sourceSpec; override : R.SourceOverride.t;}
    and sourceSpec =
      | Archive of {
          url : string;
          checksum : Checksum.t option;
        }
      | Git of {
          remote : string;
          ref : string option;
          manifest : SandboxSpec.ManifestSpec.t option;
        }
      | Github of {
          user : string;
          repo : string;
          ref : string option;
          manifest : SandboxSpec.ManifestSpec.t option;
        }
      | LocalPath of {
          path : Path.t;
          manifest : SandboxSpec.ManifestSpec.t option;
        }
      | LocalPathLink of {
          path : Path.t;
          manifest : SandboxSpec.ManifestSpec.t option;
        }
      | NoSource
      [@@deriving (eq, ord)]
  end

  module Version = struct
    type t =
      | Npm of SemverVersion.Version.t
      | Opam of OpamPackageVersion.Version.t
      | Source of Source.t
      [@@deriving (ord, eq)]
  end

  module VersionSpec = struct
    type t =
      | Npm of SemverVersion.Formula.DNF.t
      | NpmDistTag of string * SemverVersion.Version.t option
      | Opam of OpamPackageVersion.Formula.DNF.t
      | Source of SourceSpec.t
      [@@deriving (eq, ord)]
  end

  module Req = struct
    type t = {
      name: string;
      spec: VersionSpec.t;
    } [@@deriving (eq, ord)]
  end

  module Dependencies = struct
    type t =
      Req.t list
      [@@deriving (eq, ord)]
  end

  module Resolutions = struct
    type t =
      Version.t StringMap.t
      [@@deriving (eq, ord)]
  end

  module SourceOverride = struct

    type dependencyOverride =
      | Remove of string
      | Define of Req.t
      [@@deriving eq, ord]

    type envOverride =
      | Remove of string
      | Define of Env.item
      [@@deriving eq, ord]

    type exportedEnvOverride =
      | Remove of string
      | Define of ExportedEnv.item
      [@@deriving eq, ord]

    type t = {
      name : string option;
      version : string option;
      build : CommandList.t option;
      install : CommandList.t option;
      (* exportedEnv : ExportedEnv.t option; *)
      (* exportedEnvOverride : exportedEnvOverride list option; *)
      (* buildEnv : Env.t option; *)
      (* buildEnvOverride : envOverride list option; *)
      (* sandboxEnv : ExportedEnv.t option; *)
      (* sandboxEnvOverride : envOverride list option; *)
      (* dependencies : Dependencies.t option; *)
      (* dependenciesOverride : dependencyOverride list option; *)
      (* resolutions : Resolutions.t option; *)
    } [@@deriving eq, ord]
  end

end

include R
