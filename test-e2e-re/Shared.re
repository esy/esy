module System = EsyLib.System;
module Result = EsyLib.Result;
module Path = EsyLib.Path;
module Option = EsyLib.Option;
module Run = EsyLib.Run;

/* We always expect error to be `Msg */
type result('t) = Bos.OS.result('t, Rresult.R.msg);
type action = unit => result(unit);

Random.self_init();

let randBound = 20000;
let isWindows =
  switch (System.Platform.host) {
  | Windows => true
  | _ => false
  };

let currentPath = Path.currentPath();

let makePath = (~from=currentPath, toPath) => {
  Path.v(toPath) |> Path.append(from) |> Path.normalize;
};

let esyLocalPath = {
  let which = isWindows ? "where" : "which";
  let cmd = Bos.Cmd.(v("esy") % "dune" % "exec" % which % "esy");
  let res = Bos.OS.Cmd.(run_out(cmd) |> to_string(~trim=true));
  Fpath.v(Rresult.R.failwith_error_msg(res));
};

let testDir = makePath("./test-e2e-re/");

let exe = name => {
  let name = isWindows ? name ++ ".exe" : name;
  name;
};

let tempDirFromEnv = {
  let orA = d => Option.orOther(~other=d);
  let var = Bos.OS.Env.var;
  /* TODO: offer default for windows ? */
  let result =
    if (isWindows) {
      var("TEMP") |> orA(var("TMP"));
    } else {
      var("TMPDIR")
      |> orA(var("TMP"))
      |> orA(var("TEMP"))
      |> orA(Some("/tmp"));
    };
  switch (result) {
  | Some(dir) => Path.v(dir)
  | None => failwith("Could not determine temporary root directory")
  };
};

let getTempDir = folder => {
  Result.return(Path.addSeg(tempDirFromEnv, folder));
};

// Prefix can be usefull for debugging the tests
let getRandomTmpDir = (~prefix="", ()) => {
  getTempDir(prefix ++ string_of_int(Random.int(randBound)));
};

let changeCwd = newCwd => {
  let prev = Unix.getcwd();
  Unix.chdir(newCwd);
  () => Unix.chdir(prev);
};

let runRToFpathR = result =>
  switch (result |> Run.toResult) {
  | Ok(ok) => Result.return(ok)
  | Error(e) => Result.error(`Msg(e))
  };

let rExn =
  fun
  | Ok(a) => a
  | Error(`Msg(e)) => failwith(e);

let matchesRe = (s1, re) => {
  let res =
    try (Str.search_forward(re, s1, 0)) {
    | Not_found => (-1)
    };
  res != (-1);
};

let contains = (s1, s2) => {
  let re = Str.regexp_string(s2);
  matchesRe(s1, re);
};

let outdent = str => {
  let nl = Str.regexp("\n");
  let emptyLine = Str.regexp("^ +$");
  let indentation = Str.regexp("^ +[^ ]");

  let process =
    fun
    | [] => str
    | [first, ...rest] => {
        /* Find the spacing offset */
        let _ = Str.search_forward(indentation, first, 0);
        let space = Str.matched_string(first);
        let spacing = String.length(space) - 1;

        let result =
          List.fold_left(
            (str, row) =>
              if (matchesRe(row, emptyLine)) {
                str;
              } else {
                str ++ Str.string_after(row, spacing) ++ "\n";
              },
            "",
            [first, ...rest],
          );
        // Remove last endline
        String.trim(result);
      };

  process(Str.split(nl, str));
};

let join = (~separator, list) => {
  let output =
    List.fold_left((acc, item) => acc ++ separator ++ item, "", list);
  /* Remove first seperator entry */
  Str.string_after(output, String.length(separator));
};
