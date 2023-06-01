/*
 * Dumps string to file or stdout if filename == '-'
 */

open RunAsync.Syntax;

type t =
  | Stdout
  | File(Path.t);

let conv = {
  open Esy_cmdliner;
  let parse = v =>
    switch (v) {
    | "-" => Ok(Stdout)
    | _ =>
      switch (Path.ofString(v)) {
      | Ok(path) =>
        if (Path.isAbs(path)) {
          Ok(File(path));
        } else {
          Ok(File(Path.(v(Sys.getcwd()) /\/ path |> normalize)));
        }
      | Error(err) => Error(err)
      }
    };

  let print = (ppf, p) =>
    switch (p) {
    | Stdout => Format.fprintf(ppf, "-")
    | File(path) => Path.pp(ppf, path)
    };
  Arg.conv(~docv="PATH", (parse, print));
};

let dump = (filename: t, data) =>
  switch (filename) {
  | Stdout =>
    let%lwt () = Lwt_io.(write(stdout, data));
    return();
  | File(filename) => Fs.writeFile(~data, filename)
  };
