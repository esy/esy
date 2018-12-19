include EsyLib.Store;

module System = EsyLib.System;

let%test "Validate padding length on Windows is always 1, if long paths aren't supported" = {
  let prefixPath = Fpath.v("test");
  let padding = getPadding(~system=System.Platform.Windows, ~longPaths=false, prefixPath);
  switch (padding) {
  | Ok("_") => true
  | _ => false
  };
};

let%test "Validate padding length on Windows is not 1, if long paths are supported" = {
  let prefixPath = Fpath.v("test");
  let padding = getPadding(~system=System.Platform.Windows, ~longPaths=true, prefixPath);
  switch (padding) {
  | Ok("_") => false
  | Error(_) => false
  | _ => true
  };
};

let%test "Validate padding length on other platforms is not 1" = {
  let prefixPath = Fpath.v("test");
  let padding = getPadding(~system=System.Platform.Darwin, prefixPath);
  switch (padding) {
  | Ok("_") => false
  | Error(_) => false
  | _ => true
  };
};

let%test "Validate an error is given if the path is too long" = {
  let superLongPath = String.make(260, 'a');
  let prefixPath = Fpath.v(superLongPath);
  let padding = getPadding(~system=System.Platform.Darwin, prefixPath);
  switch (padding) {
  | Error(_) => true
  | _ => false
  };
};
