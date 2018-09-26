type t = Fpath.t;
type ext = Fpath.ext;

module Set = Fpath.Set;

let v = Fpath.v;
let (/) = Fpath.(/);
let (/\/) = Fpath.(/\/);

let dirSep = Fpath.dir_sep;

let hasExt = Fpath.has_ext;
let addExt = Fpath.add_ext;
let remExt = Fpath.rem_ext;
let getExt = Fpath.get_ext;

let addSeg = Fpath.add_seg;

let ofString = v => {
  let v = Fpath.of_string(v);
  (v: result(t, [ | `Msg(string)]) :> result(t, [> | `Msg(string)]));
};

let isAbs = Fpath.is_abs;
let isPrefix = Fpath.is_prefix;
let remPrefix = Fpath.rem_prefix;

let homePath = () =>
  Fpath.v(
    switch (Sys.getenv_opt("HOME"), System.Platform.host) {
    | (Some(dir), _) => dir
    | (None, System.Platform.Windows) => Sys.getenv("USERPROFILE")
    | (None, _) => failwith("Could not find HOME dir")
    },
  );
let dataPath = () =>
  Fpath.v(
    switch (System.Platform.host) {
    | System.Platform.Windows => Sys.getenv("LOCALAPPDATA")
    | _ => Sys.getenv("HOME")
    },
  );
let current = () => Run.ofBosError(Bos.OS.Dir.current());

let relativize = Fpath.relativize;
let parent = Fpath.parent;
let basename = Fpath.basename;
let append = Fpath.append;

let normalizePathSlashes = {
  let backSlashRegex = Str.regexp("\\\\");
  p => Str.global_replace(backSlashRegex, "/", p);
};

let remEmptySeg = Fpath.rem_empty_seg;
let normalize = Fpath.normalize;
let normalizeAndRemoveEmptySeg = p =>
  Fpath.rem_empty_seg(Fpath.normalize(p));

/* COMPARABLE */

let compare = Fpath.compare;

/* PRINTABLE */

let show = p => {
  let ret = Fpath.to_string(p);
  normalizePathSlashes(ret);
};

let pp = Fpath.pp;
let toPrettyString = p =>
  Run.Syntax.(
    {
      let%bind path =
        switch (remPrefix(homePath(), p)) {
        | Some(p) => return(Fpath.append(Fpath.v("~"), p))
        | None => return(p)
        };
      return(Fpath.to_string(path));
    }
  );

/* JSONABLE */

let of_yojson = (json: Yojson.Safe.json) =>
  switch (json) {
  | `String(v) =>
    switch (Fpath.of_string(v)) {
    | Ok(v) => Ok(v)
    | Error(`Msg(msg)) => Error(msg)
    }
  | _ => Error("invalid path")
  };

let to_yojson = (path: t) => `String(show(path));

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
    |> Str.global_replace(replaceSlash, "__s__")
    |> Str.global_replace(replaceDot, "__d__")
    |> Str.global_replace(replaceColon, "__c__")
    |> Str.global_replace(replaceDash, "_");
  make;
};

let safePath = {
  let replaceSlash = Str.regexp("\\/");
  let replaceColon = Str.regexp(":");
  let make = name =>
    name
    |> Str.global_replace(replaceSlash, "__s__")
    |> Str.global_replace(replaceColon, "__c__");
  make;
};
