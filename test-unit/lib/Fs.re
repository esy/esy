open EsyBuildPackage;
open Run;

module Mock: {
  module Fs: Run.T;
} = {
  let createExe = () => {
    let bytes = Bytes.create(4);
    Bytes.set_int32_ne(bytes, 0, 0xfeedfacfl);
    bytes;
  };
  let createNonExe = () => {
    let bytes = Bytes.create(4);
    Bytes.set_int32_ne(bytes, 0, 0xFFFFFFFFl);
    bytes;
  };
  module Fs = {
    open Unix;
    let nonFileStat = {
      st_dev: 0, /* Device number */
      st_ino: 0, /* Inode number */
      st_kind: S_LNK, /* Kind of the file */
      st_perm: 0, /* Access rights */
      st_nlink: 0, /* Number of links */
      st_uid: 0, /* User id of the owner */
      st_gid: 0, /* Group ID of the file's group */
      st_rdev: 0, /* Device ID (if special file) */
      st_size: 0, /* Size in bytes */
      st_atime: 0.0, /* Last access time */
      st_mtime: 0.0, /* Last modification time */
      st_ctime: 0.0 /* Last status change time */
    };
    let dirStat = {
      st_dev: 0, /* Device number */
      st_ino: 0, /* Inode number */
      st_kind: S_DIR, /* Kind of the file */
      st_perm: 0, /* Access rights */
      st_nlink: 0, /* Number of links */
      st_uid: 0, /* User id of the owner */
      st_gid: 0, /* Group ID of the file's group */
      st_rdev: 0, /* Device ID (if special file) */
      st_size: 0, /* Size in bytes */
      st_atime: 0.0, /* Last access time */
      st_mtime: 0.0, /* Last modification time */
      st_ctime: 0.0 /* Last status change time */
    };
    let fileStat = {
      st_dev: 0, /* Device number */
      st_ino: 0, /* Inode number */
      st_kind: S_REG, /* Kind of the file */
      st_perm: 0, /* Access rights */
      st_nlink: 0, /* Number of links */
      st_uid: 0, /* User id of the owner */
      st_gid: 0, /* Group ID of the file's group */
      st_rdev: 0, /* Device ID (if special file) */
      st_size: 0, /* Size in bytes */
      st_atime: 0.0, /* Last access time */
      st_mtime: 0.0, /* Last modification time */
      st_ctime: 0.0 /* Last status change time */
    };
    let read' = fpath => {
      switch (Fpath.to_string(fpath)) {
      | "/a/binary" => createExe()
      | _ => createNonExe()
      };
    };
    let read = x => return @@ Bytes.to_string @@ read'(x);
    let stat' = fpath => {
      switch (Fpath.to_string(fpath)) {
      | "/a/binary"
      | "file1"
      | "file2"
      | "file3" => fileStat
      | "dir"
      | "dirdir"
      | "dirdirdir" => dirStat
      | _ => nonFileStat
      };
    };

    let stat = fpath => return @@ stat'(fpath);
    type in_channel =
      | InputFile(string);
    type file_descr = in_channel;
    let mockInputChannel = pathStr => InputFile(pathStr);
    let fileDescriptorOfChannel = x => x;
    let withIC' = (fpath, callback, v) => {
      callback(mockInputChannel(Fpath.to_string(fpath)), v);
    };
    let withIC = (fpath, callback, v) =>
      return @@ withIC'(fpath, callback, v);
    let readBytes' = (fileDescriptor: file_descr, buffer, _start, _length) => {
      switch (fileDescriptor) {
      | InputFile(pathStr) =>
        switch (pathStr) {
        | "\\a\\binary"
        | "/a/binary" => Bytes.set_int32_ne(buffer, 0, 0xfeedfacfl)
        | "file"
        | "file1"
        | "file2"
        | "file3" => Bytes.set_int32_ne(buffer, 0, 0xffffffffl)
        | _ => failwith("Not a file: " ++ pathStr)
        }
      };
    };
    let readBytes = (fd, buffer, start, len) => {
      readBytes'(fd, buffer, start, len);
      0;
    };

    module Dir = {
      let contents' = fpath => {
        switch (Fpath.to_string(fpath)) {
        | "dirdirdir" => ["dirdir", "dir", "/a/binary", "/a/binary", "file3"]
        | "dirdir" => ["dir", "dir", "/a/binary"]
        | "dir" => ["file", "/a/binary"]
        | _ => []
        };
      };
      let contents = (~dotfiles as _=?, ~rel as _=?, x) =>
        return @@
        List.map(x =>
          switch (Fpath.of_string(x)) {
          | Ok(x) => x
          | Error(`Msg(_m)) =>
            failwith("Failed to turn " ++ x ++ " to Fpath.t")
          }
        ) @@
        contents'(x);
    };
  };
};
