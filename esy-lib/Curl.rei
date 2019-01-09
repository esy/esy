/**
 * Work with remote URLs via curl utility.
 */;

type response =
  | Success(string)
  | NotFound;

type headers = StringMap.t(string);

type url = string;

let getOrNotFound: (~accept: string=?, url) => RunAsync.t(response);

/** Return map of headers for the urls, all header names are lowercased */

let head: url => RunAsync.t(headers);

let get: (~accept: string=?, url) => RunAsync.t(string);

let download: (~output: Fpath.t, url) => RunAsync.t(unit);
