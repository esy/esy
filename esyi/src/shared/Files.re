
/* TODO use lwt-node */

let maybeStat = (path) =>
  try (Some(Unix.stat(path))) {
  | Unix.Unix_error(Unix.ENOENT, _, _) => None
  };

let expectSuccess = (msg, v) => if (v) { () } else { failwith(msg) };

[@test [
  (("/a/b/c", "/a/b/d"), "../d"),
  (("/a/b/c", "/a/b/d/e"), "../d/e"),
  (("/a/b/c", "/d/e/f"), "../../../d/e/f"),
  (("/a/b/c", "/a/b/c/d/e"), "./d/e"),
]]
let relpath = (base, path) => {
  let rec loop = (bp, pp) => {
    switch (bp, pp) {
    | ([a, ...ra], [b, ...rb]) when a == b => loop(ra, rb)
    | _ => (bp, pp)
    }
  };
  let (base, path) = loop(String.split_on_char('/', base), String.split_on_char('/', path));
  String.concat("/",
  (base == [] ? ["."] : List.map((_) => "..", base))
  @ path
  )
};

let symlink = (source, dest) => {
  Unix.symlink(relpath(Filename.dirname(dest), source), dest)
};

let readFile = path => {
  switch (maybeStat(path)) {
  | Some({Unix.st_kind: Unix.S_REG}) =>
    let ic = open_in(path);
    let try_read = () =>
      switch (input_line(ic)) {
      | exception End_of_file => None
      | x => Some(x)
      };
    let rec loop = (acc) =>
      switch (try_read()) {
      | Some(s) => loop([s, ...acc])
      | None =>
        close_in(ic);
        List.rev(acc)
      };
    let text = loop([]) |> String.concat(String.make(1, '\n'));
    Some(text)
  | _ => None
  }
};

let writeFile = (path, contents) => {
  try {
    let out = open_out(path);
    output_string(out, contents);
    close_out(out);
    true
  } {
    | _ => false
  }
};

let copy = (~source, ~dest) =>
  switch (maybeStat(source)) {
  | None => false
  | Some({Unix.st_perm}) =>
    let fs = Unix.openfile(source, [Unix.O_RDONLY], st_perm);
    let fd = Unix.openfile(dest, [Unix.O_WRONLY, Unix.O_CREAT, Unix.O_TRUNC], st_perm);
    let buffer_size = 8192;
    let buffer = Bytes.create(buffer_size);
    let rec copy_loop = () =>
      switch (Unix.read(fs, buffer, 0, buffer_size)) {
      | 0 => ()
      | r =>
        ignore(Unix.write(fd, buffer, 0, r));
        copy_loop()
      };
    copy_loop();
    Unix.close(fs);
    Unix.close(fd);
    true
  };

let exists = (path) =>
  switch (maybeStat(path)) {
  | None => false
  | Some(_) => true
  };

let isFile = path => switch (maybeStat(path)) {
| Some({Unix.st_kind: Unix.S_REG}) => true
| _ => false
};

let isDirectory = path => switch (maybeStat(path)) {
| Some({Unix.st_kind: Unix.S_DIR}) => true
| _ => false
};

let readDirectory = (dir) => {
  let maybeGet = (handle) =>
    try (Some(Unix.readdir(handle))) {
    | End_of_file => None
    };
  let rec loop = (handle) =>
    switch (maybeGet(handle)) {
    | None =>
      Unix.closedir(handle);
      []
    | Some(name) when name == Filename.current_dir_name || name == Filename.parent_dir_name => loop(handle)
    | Some(name) => [name, ...loop(handle)]
    };
  loop(Unix.opendir(dir))
};

let rec mkdirp = (dest) =>
  if (! exists(dest)) {
    let parent = Filename.dirname(dest);
    mkdirp(parent);
    Unix.mkdir(dest, 0o740)
  };

let rec copyDeep = (~source, ~dest) => {
  mkdirp(Filename.dirname(dest));
  switch (maybeStat(source)) {
  | None => ()
  | Some({Unix.st_kind: Unix.S_DIR}) =>
    readDirectory(source)
    |> List.iter(
         (name) =>
           copyDeep(~source=Filename.concat(source, name), ~dest=Filename.concat(dest, name))
       )
  | Some({Unix.st_kind: Unix.S_REG}) => copy(~source, ~dest) |> ignore
  | _ => ()
  }
};

let rec removeDeep = path => {
  switch (Unix.lstat(path)) {
  | exception Unix.Unix_error(Unix.ENOENT, _, _) => ()
  | {Unix.st_kind: Unix.S_LNK} => {
    Unix.unlink(path)
  }
  | {Unix.st_kind: Unix.S_DIR} =>
    readDirectory(path)
    |> List.iter((name) => removeDeep(Filename.concat(path, name)));
    Unix.rmdir(path);
  | _ => Unix.unlink(path)
  }
};

let (/+) = Filename.concat;

let crawl = (base) => {
  let rec inner = (base, rel, fn) => {
    readDirectory(base) |> List.iter(name => {
      let full = base /+ name;
      if (isDirectory(full)) {
        inner(full, rel /+ name, fn)
      } else {
        fn(rel /+ name, full)
      }
    })
  };
  inner(base, "")
};