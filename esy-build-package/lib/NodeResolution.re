module PackageJson = {
  type t = {
    name: string,
    main: option(string),
    browser: option(string)
  };
  let of_json = data =>
    Yojson.Safe.Util.(
      try {
        let name = member("name", data) |> to_string;
        let main = member("main", data) |> to_string_option;
        let browser = member("browser", data) |> to_string_option;
        Result.Ok({name, main, browser});
      } {
      | Type_error(_) => Result.Error("Error parsing package.json")
      }
    );
  let of_string = data => {
    let data = Yojson.Safe.from_string(data);
    of_json(data);
  };
};

let stat_option = (path: Fpath.t) =>
  switch (Bos.OS.Path.stat(path)) {
  | Ok(stat) => Some(stat)
  | Error(_) => None
  };

let package_entry_point = (package_json_path: Fpath.t) => {
  open Run;
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
  switch main_value {
  | Some(main_value) =>
    let%bind main_path = Fpath.of_string(main_value);
    Ok(Fpath.(package_path /\/ main_path));
  | None => Ok(Fpath.(package_path / "index.js"))
  };
};

/** Try to resolve an absolute path */
let resolve_path = path =>
  Run.(
    switch (stat_option(path)) {
    | None => Ok(None)
    | Some(stat) =>
      switch stat.st_kind {
      | Unix.S_DIR =>
        /* Check if directory contains package.json and read entry point from
           there if any */
        let package_json_path = Fpath.(path / "package.json");
        if%bind (exists(package_json_path)) {
          let%bind entry_point = package_entry_point(package_json_path);
          Ok(Some(entry_point));
        } else {
          /*** Check if directory contains index.js and return it if found */
          let index_js_path = Fpath.(path / "index.js");
          if%bind (exists(index_js_path)) {
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
let resolve_extensionless_path = (path: Fpath.t) =>
  Run.(
    switch%bind (resolve_path(path)) {
    | None => resolve_path(Fpath.add_ext(".js", path))
    | Some(_) as res => Ok(res)
    }
  );

/** Try to resolve a package */
let rec resolve_package =
        (package: string, segments: option(list(string)), basedir: Fpath.t) => {
  open Run;
  let node_modules_path = basedir / "node_modules";
  let package_path = node_modules_path / package;
  if%bind (exists(node_modules_path)) {
    if%bind (exists(package_path)) {
      switch segments {
      | None => resolve_extensionless_path(package_path)
      | Some(segments) =>
        let path = List.fold_left((p, x) => p / x, package_path, segments);
        resolve_extensionless_path(path);
      };
    } else {
      let next_basedir = Fpath.parent(basedir);
      if (next_basedir === basedir) {
        Ok(None);
      } else {
        resolve_package(package, segments, next_basedir);
      };
    };
  } else {
    let next_basedir = Fpath.parent(basedir);
    if (next_basedir === basedir) {
      Ok(None);
    } else {
      resolve_package(package, segments, next_basedir);
    };
  };
};

let resolve = (path, basedir) =>
  Run.(
    switch path {
    | "" => Ok(None)
    | path =>
      switch path.[0] {
      /* relative module path */
      | '.' =>
        let%bind path = Fpath.of_string(path);
        let path = path |> Fpath.append(basedir) |> Fpath.normalize;
        resolve_extensionless_path(path);
      /* absolute module path */
      | '/' =>
        let%bind path = Fpath.of_string(path);
        resolve_extensionless_path(path);
      /* scoped package */
      | '@' =>
        let (package, segments) =
          switch (String.split_on_char('/', path)) {
          | [] => (None, None)
          | [_scope] => (None, None)
          | [scope, package] => (Some(scope ++ "/" ++ package), None)
          | [scope, package, ...rest] => (
              Some(scope ++ "/" ++ package),
              Some(rest)
            )
          };
        switch package {
        | None => Ok(None)
        | Some(package) => resolve_package(package, segments, basedir)
        };
      /* package */
      | _ =>
        let (package, segments) =
          switch (String.split_on_char('/', path)) {
          | [] => (None, None)
          | [package] => (Some(package), None)
          | [package, ...rest] => (Some(package), Some(rest))
          };
        switch package {
        | None => Ok(None)
        | Some(package) => resolve_package(package, segments, basedir)
        };
      }
    }
  );
