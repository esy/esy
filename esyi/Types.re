module Path = EsyLib.Path;

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
