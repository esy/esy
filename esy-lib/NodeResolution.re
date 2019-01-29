module PackageJson = {
  type t = {
    name: string,
    main: option(string),
    browser: option(string),
  };
  let of_json = data =>
    Yojson.Safe.Util.(
      try (
        {
          let name = member("name", data) |> to_string;
          let main = member("main", data) |> to_string_option;
          let browser = member("browser", data) |> to_string_option;
          Result.Ok({name, main, browser});
        }
      ) {
      | Type_error(_) => Result.Error("Error parsing package.json")
      }
    );
  let of_string = data => {
    let data = Yojson.Safe.from_string(data);
    of_json(data);
  };
};

let stat = (path: Fpath.t) =>
  switch (Bos.OS.Path.stat(path)) {
  | Ok(stat) => Some(stat)
  | Error(_) => None
  };

let package_entry_point = (package_json_path: Fpath.t) => {
  open Result.Syntax;
  let package_path = Fpath.parent(package_json_path);
  let%bind main_value = {
    let%bind data = Bos.OS.File.read(package_path);
    switch (PackageJson.of_string(data)) {
    | Result.Ok(package) => Ok(package.PackageJson.main)
    | Result.Error(msg) =>
      /*** TODO: missing error handling here */
      Error(`Msg(msg))
    };
  };
  switch (main_value) {
  | Some(main_value) =>
    let%bind main_path = Fpath.of_string(main_value);
    Ok(Fpath.(package_path /\/ main_path));
  | None => Ok(Fpath.(package_path / "index.js"))
  };
};

let (/) = Fpath.(/);

let rec realpath = (p: Fpath.t) => {
  open Result.Syntax;
  let%bind p =
    if (Fpath.is_abs(p)) {
      Ok(p);
    } else {
      let%bind cwd = Bos.OS.Dir.current();
      Ok(p |> Fpath.append(cwd) |> Fpath.normalize);
    };
  let _realpath = (p: Fpath.t) => {
    let isSymlinkAndExists = p =>
      switch (Bos.OS.Path.symlink_stat(p)) {
      | Ok({Unix.st_kind: Unix.S_LNK, _}) => Ok(true)
      | _ => Ok(false)
      };
    if (Fpath.is_root(p)) {
      Ok(p);
    } else {
      let%bind isSymlink = isSymlinkAndExists(p);
      if (isSymlink) {
        let%bind target = Bos.OS.Path.symlink_target(p);
        realpath(
          target |> Fpath.append(Fpath.parent(p)) |> Fpath.normalize,
        );
      } else {
        let parent = p |> Fpath.parent |> Fpath.rem_empty_seg;
        let%bind parent = realpath(parent);
        Ok(parent / Fpath.basename(p));
      };
    };
  };
  let%bind p = _realpath(p);
  let p =
    // on win we can get path swith \??\ prefix, remove it
    switch (System.Platform.host) {
    | Windows =>
      let p = Path.show(p);
      let len = String.length(p);
      if (len >= 4 && String.sub(p, 0, 4) == "\\??\\") {
        Path.v(String.sub(p, 4, len - 4));
      } else {
        Path.v(p);
      };
    | _ => p
    };
  return(p);
};

/** Try to resolve an absolute path */
let resolvePath = path =>
  Result.Syntax.(
    switch (stat(path)) {
    | None => Ok(None)
    | Some(stat) =>
      switch (stat.st_kind) {
      | Unix.S_DIR =>
        /* Check if directory contains package.json and read entry point from
           there if any */
        let package_json_path = Fpath.(path / "package.json");
        if%bind (Bos.OS.Path.exists(package_json_path)) {
          let%bind entry_point = package_entry_point(package_json_path);
          Ok(Some(entry_point));
        } else {
          /*** Check if directory contains index.js and return it if found */
          let index_js_path = Fpath.(path / "index.js");
          if%bind (Bos.OS.Path.exists(index_js_path)) {
            Ok(Some(index_js_path));
          } else {
            Ok(None);
          };
        };
      | Unix.S_REG => Ok(Some(path))
      /* TODO: handle symlink */
      | _ => Ok(None)
      }
    }
  );

/** Try to resolve an absolute path with different extensions */
let resolveExtensionlessPath = (path: Fpath.t) => {
  open Result.Syntax;
  switch%bind (resolvePath(path)) {
  | None => resolvePath(Fpath.add_ext(".js", path))
  | Some(_) as res => Ok(res)
  };
};

/** Try to resolve a package */
let rec resolvePackage =
        (package: Path.t, segments: option(list(string)), basedir: Fpath.t) => {
  open Result.Syntax;
  let node_modules_path = Path.(basedir / "node_modules");
  let package_path = Path.append(node_modules_path, package);
  if%bind (Bos.OS.Path.exists(node_modules_path)) {
    if%bind (Bos.OS.Path.exists(package_path)) {
      switch (segments) {
      | None => resolveExtensionlessPath(package_path)
      | Some(segments) =>
        let path =
          List.fold_left(
            ~f=(p, x) => Path.(p / x),
            ~init=package_path,
            segments,
          );
        resolveExtensionlessPath(path);
      };
    } else {
      let next_basedir = Fpath.parent(basedir);
      if (next_basedir === basedir) {
        Ok(None);
      } else {
        resolvePackage(package, segments, next_basedir);
      };
    };
  } else {
    let next_basedir = Fpath.parent(basedir);
    if (next_basedir === basedir) {
      Ok(None);
    } else {
      resolvePackage(package, segments, next_basedir);
    };
  };
};

type req = string;

let defaultBaseDir = ref(None);

let resolve = (~basedir=?, req) => {
  open Result.Syntax;
  let%bind basedir =
    switch (basedir) {
    | Some(basedir) => return(basedir)
    | None =>
      switch (defaultBaseDir^) {
      | Some(basedir) => return(basedir)
      | None =>
        let program = Sys.executable_name;
        let%bind program = realpath(Path.v(program));
        let basedir = Fpath.parent(program);
        defaultBaseDir := Some(basedir);
        return(basedir);
      }
    };

  let someOrError = v =>
    switch%bind (v) {
    | Some(v) => Ok(v)
    | None =>
      let msg =
        Printf.sprintf(
          "Unable to resolve %s from %s",
          req,
          Path.show(basedir),
        );
      Error(`Msg(msg));
    };

  let res =
    switch (req) {
    | "" => Error(`Msg("empty request"))
    | path =>
      switch (path.[0]) {
      /* relative module path */
      | '.' =>
        let%bind path = Fpath.of_string(path);
        let path = path |> Fpath.append(basedir) |> Fpath.normalize;
        someOrError(resolveExtensionlessPath(path));
      /* absolute module path */
      | '/' =>
        let%bind path = Fpath.of_string(path);
        someOrError(resolveExtensionlessPath(path));
      /* scoped package */
      | '@' =>
        let (package, segments) =
          switch (String.split_on_char('/', path)) {
          | [] => (None, None)
          | [_scope] => (None, None)
          | [scope, package] => (Some(Path.(v(scope) / package)), None)
          | [scope, package, ...rest] => (
              Some(Path.(v(scope) / package)),
              Some(rest),
            )
          };
        switch (package) {
        | None => Error(`Msg("invalid request: " ++ req))
        | Some(package) =>
          someOrError(resolvePackage(package, segments, basedir))
        };
      /* package */
      | _ =>
        let (package, segments) =
          switch (String.split_on_char('/', path)) {
          | [] => (None, None)
          | [package] => (Some(Path.v(package)), None)
          | [package, ...rest] => (Some(Path.v(package)), Some(rest))
          };
        switch (package) {
        | None => Error(`Msg("invalid request: " ++ req))
        | Some(package) =>
          someOrError(resolvePackage(package, segments, basedir))
        };
      }
    };
  (res: result(_, [ | `Msg(string)]) :> result(_, [> | `Msg(string)]));
};
