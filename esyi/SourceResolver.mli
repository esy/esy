(**

  Loading packages from sources and collecting overrides.

 *)

type resolution = {

  overrides : Package.Overrides.t;
  (** A set of overrides. *)

  source : Source.t;
  (** Final source. *)

  manifest : manifest option;
  (* In case no manifest is found - None is returned. *)
}

and manifest = {
  kind : ManifestSpec.Filename.kind;
  filename : string;
  data : string;
}

val resolve :
  ?overrides:Package.Overrides.t
  -> cfg:Config.t
  -> root:Path.t
  -> Source.t
  -> resolution RunAsync.t
(**

  Resolve [source] and produce a [resolution].

  A set of predefined [overrides] can be passed, in this case newly discovered
  overrides are being appended to it.

  Argument [root] is used to resolve [Source.LocalPath] and
  [Source.LocalPathLink] sources.

 *)
