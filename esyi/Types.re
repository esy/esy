module Path = EsyLib.Path;

[@deriving yojson]
type npmRange = GenericVersion.range(NpmVersion.t);

[@deriving yojson]
type opamFile = (Json.t, list((Path.t, string)), list(string));

module PendingSource = {
  [@deriving yojson]
  type t =
    | WithOpamFile(t, opamFile)
    /* url & checksum */
    | Archive(string, option(string))
    /* url & ref */
    | GitSource(string, option(string))
    | GithubSource(string, string, option(string))
    | File(string)
    | NoSource;
};

let resolvedPrefix = "esyi5-";

let opamFromNpmConcrete = ((major, minor, patch, rest)) => {
  let v =
    switch (rest) {
    | Some(rest) => Printf.sprintf("%i.%i.%i%s", major, minor, patch, rest)
    | None => Printf.sprintf("%i.%i.%i", major, minor, patch)
    };
  OpamVersioning.Version.parseExn(v);
};
