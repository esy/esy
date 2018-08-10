include Fpath;

let show = to_string;
let addExt = add_ext;
let addSeg = add_seg;
let toString = to_string;
let isPrefix = is_prefix;
let remPrefix = rem_prefix;

let user = () => Run.ofBosError(Bos.OS.Dir.user());
let current = () => Run.ofBosError(Bos.OS.Dir.current());

let backSlashRegex = Str.regexp("\\\\");

let normalizePathSlashes = p => Str.global_replace(backSlashRegex, "/", p);

/**
 * Convert a path to a string and replace a prefix to ~ if it's happened to be a
 * a user home directory.
 */
let toPrettyString = p =>
  Run.Syntax.(
    {
      let%bind path = {
        let%bind user = user();
        switch (remPrefix(user, p)) {
        | Some(p) => return(append(v("~"), p))
        | None => return(p)
        };
      };
      return(toString(path));
    }
  );

/*
 * yojson protocol
 */

let of_yojson = (json: Yojson.Safe.json) =>
  switch (json) {
  | `String(v) =>
    switch (Fpath.of_string(v)) {
    | Ok(v) => Ok(v)
    | Error(`Msg(msg)) => Error(msg)
    }
  | _ => Error("invalid path")
  };

let to_yojson = (path: t) => `String(to_string(path));

let safeSeg = {
  let replaceAt = Str.regexp("@");
  let replaceUnderscore = Str.regexp("_+");
  let replaceSlash = Str.regexp("\\/");
  let replaceDot = Str.regexp("\\.");
  let replaceDash = Str.regexp("\\-");
  let replaceColon = Str.regexp(":");
  let make = (name: string) =>
    name
    |> String.lowercase_ascii
    |> Str.global_replace(replaceAt, "")
    |> Str.global_replace(replaceUnderscore, "__")
    |> Str.global_replace(replaceSlash, "__slash__")
    |> Str.global_replace(replaceDot, "__dot__")
    |> Str.global_replace(replaceColon, "__colon__")
    |> Str.global_replace(replaceDash, "_");
  make;
};

let safePath = {
  let replaceSlash = Str.regexp("\\/");
  let replaceColon = Str.regexp(":");
  let make = name =>
    name
    |> Str.global_replace(replaceSlash, "__slash__")
    |> Str.global_replace(replaceColon, "__colon__");
  make;
};
