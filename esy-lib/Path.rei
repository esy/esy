/**

  File system path.

 */

type t = Fpath.t;
type ext = Fpath.ext;

let v : string => t;
let (/) : t => string => t;
let (/\/) : t => t => t;

let addSeg : (t, string) => t;
let append : (t, t) => t;

let ofString : string => result(t, [> |`Msg(string)]);
let current : unit => Run.t(t);
let homeDir : unit => Run.t(t);
let dataPath : unit => Run.t(t);

let isPrefix : (t, t) => bool;
let remPrefix : (t, t) => option(t);

let isAbs : (t) => bool;
let basename : t => string;
let parent : t => t;
let relativize : (~root:t, t) => option(t);

let addExt : (ext, t) => t;
let hasExt : (ext, t) => bool;
let remExt : (~multi: bool=?, t) => t;
let getExt : (~multi: bool=?, t) => ext;

let dirSep : string;

include S.PRINTABLE with type t := t;
include S.COMPARABLE with type t := t;
include S.JSONABLE with type t := t;

module Set : (module type of Fpath.Set);

let safeSeg : string => string;
let safePath : string => string;

let remEmptySeg : t => t;
let normalize : t => t;
let normalizePathSlashes : string => string;
let normalizeAndRemoveEmptySeg : t => t;

let toPrettyString : t => Run.t(string);
