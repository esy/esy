/**

  Download URls.

  The implementation uses curl command.

  */

/** Get an URL and return the response's body */
let get : string => RunAsync.t(string);

/** Get an URL and store the response's body as [output] path on fs */
let download : (~output: Fpath.t, string) => RunAsync.t(unit)
