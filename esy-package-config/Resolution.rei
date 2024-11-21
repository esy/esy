/**

   Resolutions are package sources/version and optional build overrides tuples
   representing all packages.

   {[
     (source | version , option(override))
   ]}

   esy classifies all the packages/dependencies as,

   1. Packages specified with versions (versions as per the registry/repository)
   2. Packages specified with a URL to the sources of the package. Could be git, or
      a tarball (gz, xz, tar, zstd etc).

   Packages, up until the installation phase, must contain information about
   dependencies, version, name etc. But not necessarily commands to build them,
   because JS packages dont need them.

   To model this, we consider every package to be a overridden formula, with
   overrides being optional. Overrides, as the name suggests, contain extra
   fields that could be overridden.

   Was it absolutely necessary to model them like this? No. Alternative design/suggestions
   are welcome.

   Right now, overrides are not optional in [SourceOverride]s. This could be improved. Doing
   so would allow for NPM packages to be linked in from Github directly. Not sure, if we can
   do this reliably right now.

   Thus, resolutions are either Version overrides or source overrides, with overrides
   represented as optional JSON objects.

*/

type t = {
  name: string,
  resolution,
}
and resolution =
  | VersionOverride({
      version: Version.t,
      override: option(Json.t),
    })
  | SourceOverride({
      source: Source.t,
      override: Json.t,
    });

let resolution_of_yojson: Json.decoder(resolution);
let resolution_to_yojson: Json.encoder(resolution);

let digest: t => Digestv.t;
let source: t => option(Source.t);

include S.COMPARABLE with type t := t;
include S.PRINTABLE with type t := t;
