module rec R : sig

  module Command : sig
    type t =
      | Parsed of string list
      | Unparsed of string
    [@@deriving (show, eq, ord)]

  end

  module CommandList : sig

    type t =
      Command.t list option
      [@@deriving (show, eq, ord)]
  end

  module Env : sig

    type item = {
      name : string;
      value : string;
    }
    [@@deriving (show, eq, ord)]

    type t =
      item list
      [@@deriving (show, eq, ord)]
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
      [@@deriving (show, eq, ord)]

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
      [@@deriving ord, eq]
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
      [@@deriving (eq, ord)]
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
      [@@deriving (eq, ord)]
  end

  module Req : sig
    type t = {
      name: string;
      spec: VersionSpec.t;
    } [@@deriving (eq, ord)]
  end

  module Dependencies : sig
    type t =
      Req.t list
      [@@deriving (eq, ord)]
  end

  module Resolutions : sig
    type t =
      Version.t StringMap.t
      [@@deriving (eq, ord)]
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
      build : string list list option;
      install : string list list;
      exportedEnv : ExportedEnv.t option;
      exportedEnvOverride : exportedEnvOverride list option;
      buildEnv : Env.t option;
      buildEnvOverride : envOverride list option;
      sandboxEnv : ExportedEnv.t option;
      sandboxEnvOverride : envOverride list option;
      dependencies : Dependencies.t option;
      dependenciesOverride : dependencyOverride list option;
      resolutions : Resolutions.t option;
    }
    [@@deriving eq, ord]
  end

end = struct

  module Command = struct

    type t =
      | Parsed of string list
      | Unparsed of string
      [@@deriving (show, eq, ord)]
  end

  module CommandList = struct

    type t =
      Command.t list option
      [@@deriving (show, eq, ord)]
  end

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
      build : string list list option;
      install : string list list;
      exportedEnv : ExportedEnv.t option;
      exportedEnvOverride : exportedEnvOverride list option;
      buildEnv : Env.t option;
      buildEnvOverride : envOverride list option;
      sandboxEnv : ExportedEnv.t option;
      sandboxEnvOverride : envOverride list option;
      dependencies : Dependencies.t option;
      dependenciesOverride : dependencyOverride list option;
      resolutions : Resolutions.t option;
    } [@@deriving eq, ord]
  end

end

include R
