open EsyPackageConfig

(**

  Loading packages from sources and collecting overrides.

 *)

type resolution = {

  overrides : Overrides.t;
  (** A set of overrides. *)

  dist : Dist.t;
  (** Final source. *)

  manifest : manifest option;
  (* In case no manifest is found - None is returned. *)

  paths : Path.Set.t;
  (* Local paths used to read manifests metadata. *)
}

and manifest = {
  kind : ManifestSpec.kind;
  filename : string;
  suggestedPackageName : string;
  data : string;
}

val resolve :
  ?overrides:Overrides.t
  -> cfg:Config.t
  -> sandbox:SandboxSpec.t
  -> Dist.t
  -> resolution RunAsync.t
(**

  Resolve [source] and produce a [resolution].

  A set of predefined [overrides] can be passed, in this case newly discovered
  overrides are being appended to it.

  Argument [root] is used to resolve [Source.LocalPath] and
  [Source.LocalPathLink] sources.

 *)
