module Path = EsyLib.Path;

[@deriving ord]
type alpha =
  | Alpha(string, option(num))
and num =
  | Num(int, option(alpha));

let alpha_to_yojson = (Alpha(text, num)) => {
  let rec lnum = num =>
    switch (num) {
    | None => []
    | Some(Num(n, a)) => [`Int(n), ...lalpha(a)]
    }
  and lalpha = alpha =>
    switch (alpha) {
    | None => []
    | Some(Alpha(a, n)) => [`String(a), ...lnum(n)]
    };
  `List([`String(text), ...lnum(num)]);
};

let alpha_of_yojson = json =>
  Result.Syntax.(
    switch (json) {
    | `List(items) =>
      let rec lnum = items =>
        switch (items) {
        | [] => Ok(None)
        | [`Int(n), ...rest] =>
          let%bind rest = lalpha(rest);
          return(Some(Num(n, rest)));
        | _ => Error("Num should be a number")
        }
      and lalpha = items =>
        switch (items) {
        | [] => Ok(None)
        | [`String(n), ...rest] =>
          let%bind rest = lnum(rest);
          return(Some(Alpha(n, rest)));
        | _ => Error("Alpha should be string")
        };
      let%bind v = lalpha(items);
      switch (v) {
      | None => Error("No alpha")
      | Some(v) => Ok(v)
      };
    | _ => Result.Error("Alpha should be a list")
    }
  );

[@deriving (ord, yojson)]
type opamConcrete = alpha;

[@deriving yojson]
type opamRange = GenericVersion.range(opamConcrete);

[@deriving yojson]
type npmRange = GenericVersion.range(NpmVersion.t);

let rec viewOpamConcrete = (Alpha(a, na)) =>
  switch (na) {
  | None => a
  | Some(b) => a ++ viewNum(b)
  }
and viewNum = (Num(a, na)) =>
  string_of_int(a)
  ++ (
    switch (na) {
    | None => ""
    | Some(a) => viewOpamConcrete(a)
    }
  );

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

let opamFromNpmConcrete = ((major, minor, patch, rest)) =>
  Alpha(
    "",
    Some(
      Num(
        major,
        Some(
          Alpha(
            ".",
            Some(
              Num(
                minor,
                Some(
                  Alpha(
                    ".",
                    Some(
                      Num(
                        patch,
                        switch (rest) {
                        | None => None
                        | Some(rest) => Some(Alpha(rest, None))
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
