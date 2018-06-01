open OpamParserTypes;

type manifest = {
  fileName: string,
  build: list(list(string)),
  install: list(list(string)),
  patches: list(string), /* these should be absolute */
  files: list((Path.t, string)), /* relname, sourcetext */
  dependencies: PackageJson.Dependencies.t,
  buildDependencies: PackageJson.Dependencies.t,
  devDependencies: PackageJson.Dependencies.t,
  peerDependencies: PackageJson.Dependencies.t,
  optDependencies: PackageJson.Dependencies.t,
  available: bool,
  /* TODO optDependencies (depopts) */
  source: Types.PendingSource.t,
  exportedEnv: PackageJson.ExportedEnv.t,
};

module ThinManifest = {
  type t = {
    name: string,
    opamFile: Path.t,
    urlFile: Path.t,
    version: Types.opamConcrete,
  };
};

let rec findVariable = (name, items) =>
  switch (items) {
  | [] => None
  | [Variable(_, n, v), ..._] when n == name => Some(v)
  | [_, ...rest] => findVariable(name, rest)
  };

let opName = op =>
  switch (op) {
  | `Leq => "<="
  | `Lt => "<"
  | `Neq => "!="
  | `Eq => "="
  | `Geq => ">="
  | `Gt => ">"
  };

let withScope = name => "@opam/" ++ name;

let withoutScope = fullName => {
  let ln = 6;
  if (String.sub(fullName, 0, ln) != "@opam/") {
    failwith("Opam name not prefixed: " ++ fullName);
  };
  String.sub(fullName, ln, String.length(fullName) - ln);
};

let toDep = opamvalue => {
  let (name, s, typ) = OpamVersion.toDep(opamvalue);
  (withScope(name), s, typ);
};

let processDeps = (fileName, deps) => {
  let deps =
    switch (deps) {
    | None => []
    | Some(List(_, items)) => items
    | Some(Group(_, items)) => items
    | Some(String(pos, value)) => [String(pos, value)]
    | Some(contents) =>
      failwith(
        "Can't handle the dependencies "
        ++ fileName
        ++ " "
        ++ OpamPrinter.value(contents),
      )
    };
  List.fold_left(
    ((deps, buildDeps, devDeps), dep) => {
      let (name, dep, typ) =
        try (toDep(dep)) {
        | Failure(f) =>
          print_endline("Failed to process dep: " ++ f);
          print_endline(fileName);
          failwith("bad");
        };
      switch (typ) {
      | `Link => ([(name, dep), ...deps], buildDeps, devDeps)
      | `Build => (deps, [(name, dep), ...buildDeps], devDeps)
      | `Test => (deps, buildDeps, [(name, dep), ...devDeps])
      };
    },
    ([], [], []),
    deps,
  );
};

let filterMap = (fn, items) =>
  List.map(fn, items)
  |> List.filter(x => x != None)
  |> List.map(x =>
       switch (x) {
       | Some(x) => x
       | None => assert(false)
       }
     );

/** TODO handle more variables */
let variables = ((name, version)) => [
  ("jobs", "4"),
  ("make", "make"),
  ("ocaml-native", "true"),
  ("ocaml-native-dynlink", "true"),
  ("bin", "$cur__install/bin"),
  ("lib", "$cur__install/lib"),
  ("man", "$cur__install/man"),
  ("share", "$cur__install/share"),
  ("pinned", "false"),
  ("name", name),
  ("version", OpamVersion.viewAlpha(version)),
  ("prefix", "$cur__install"),
];

let cleanEnvName = Str.global_replace(Str.regexp("-"), "_");

/* [@test */
/*   [ */
/*     ((Str.regexp("a\\(.\\)"), String.uppercase_ascii, "applae"), "PplE"), */
/*     ((Str.regexp("A\\(.\\)"), String.lowercase_ascii, "HANDS"), "HnDS"), */
/*   ] */
/* ] */
let replaceGroupWithTransform = (rx, transform, string) =>
  Str.global_substitute(
    rx,
    s => transform(Str.matched_group(1, s)),
    string,
  );

/* [@test */
/*   [ */
/*     ( */
/*       (("awesome", Types.Alpha("", None)), "--%{fmt:enable}%-fmt"), */
/*       "--${fmt_enable:-disable}-fmt", */
/*     ), */
/*   ] */
/* ] */
let replaceVariables = (info, string) => {
  let string =
    string
    |> replaceGroupWithTransform(
         Str.regexp("%{\\([^}]+\\):installed}%"), name =>
         "${" ++ cleanEnvName(name) ++ "_installed:-false}"
       )
    |> replaceGroupWithTransform(Str.regexp("%{\\([^}]+\\):enable}%"), name =>
         "${" ++ cleanEnvName(name) ++ "_enable:-disable}"
       )
    |> replaceGroupWithTransform(Str.regexp("%{\\([^}]+\\):version}%"), name =>
         "${" ++ cleanEnvName(name) ++ "_version}"
       )
    |> replaceGroupWithTransform(Str.regexp("%{\\([^}]+\\):bin}%"), name =>
         "${" ++ cleanEnvName(name) ++ ".bin}"
       )
    |> replaceGroupWithTransform(Str.regexp("%{\\([^}]+\\):share}%"), name =>
         "${" ++ cleanEnvName(name) ++ ".share}"
       )
    |> replaceGroupWithTransform(Str.regexp("%{\\([^}]+\\):lib}%"), name =>
         "${" ++ cleanEnvName(name) ++ ".lib}"
       );
  List.fold_left(
    (string, (name, res)) =>
      Str.global_replace(
        Str.regexp_string("%{" ++ name ++ "}%"),
        res,
        string,
      ),
    string,
    variables(info),
  );
};

/* [@test [({|"install" {!preinstalled}|}, Some("install"))]] */
/* [@test.call */
/*   string => */
/*     processCommandItem( */
/*       ("something", Alpha("a", None)), */
/*       OpamParser.value_from_string(string, "wat") */
/*     ) */
/* ] */
let processCommandItem = (info, item) =>
  switch (item) {
  | String(_, name) => Some(replaceVariables(info, name))
  | Ident(_, ident) =>
    switch (List.assoc_opt(ident, variables(info))) {
    | Some(string) => Some(string)
    | None =>
      print_endline("\226\154\160\239\184\143 Missing vbl " ++ ident);
      None;
    }
  | Option(_, _, [Ident(_, "preinstalled")]) =>
    /** Skipping preinstalled */ None
  | Option(_, _, [String(_, _something)]) =>
    /* String options like "%{react:installed}%" are not currently supported */
    None
  | Option(_, String(_, name), [Pfxop(_, `Not, Ident(_, "preinstalled"))]) =>
    /** Not skipping not preinstalled */ Some(replaceVariables(info, name))
  | _ =>
    /** TODO handle  "--%{text:enable}%-text" {"%{react:installed}%"} correctly */
    print_endline("Bad build arg " ++ OpamPrinter.value(item));
    None;
  };

let processCommand = (info, items) =>
  items |> filterMap(processCommandItem(info));

/** TODO handle optional build things */
let processCommandList = (info, item) =>
  switch (item) {
  | None => []
  | Some(List(_, items))
  | Some(Group(_, items)) =>
    switch (items) {
    | [String(_) | Ident(_), ..._rest] => [items |> processCommand(info)]
    | _ =>
      items
      |> filterMap(item =>
           switch (item) {
           | List(_, items) => Some(processCommand(info, items))
           | Option(_, List(_, items), _) =>
             Some(processCommand(info, items))
           | _ =>
             print_endline(
               "Skipping a non-list build thing " ++ OpamPrinter.value(item),
             );
             None;
           }
         )
    }
  | Some(Ident(_, ident)) =>
    switch (List.assoc_opt(ident, variables(info))) {
    | Some(string) => [[string]]
    | None =>
      print_endline("\226\154\160\239\184\143 Missing vbl " ++ ident);
      [];
    }
  | Some(item) =>
    failwith(
      "Unexpected type for a command list: " ++ OpamPrinter.value(item),
    )
  };

/** TODO handle "patch-ocsigen-lwt-101.diff" {os = "darwin"} correctly */
/* [@test */
/*   [ */
/*     ( */
/*       {|["patch-ocsigen-lwt-101.diff" {os = "darwin"}]|}, */
/*       ["patch-ocsigen-lwt-101.diff"] */
/*     ), */
/*     ({|["openbsd.diff" {os = "openbsd"}]|}, []) */
/*   ] */
/* ] */
/* [@test.call */
/*   string => */
/*     processStringList(Some(OpamParser.value_from_string(string, "wat"))) */
/* ] */
/* [@test.print (fmt, x) => Format.fprintf(fmt, "%s", String.concat(", ", x))] */
let processStringList = item => {
  let items =
    switch (item) {
    | None => []
    | Some(List(_, items))
    | Some(Group(_, items)) => items
    | Some(item) =>
      failwith(
        "Unexpected type for a string list: " ++ OpamPrinter.value(item),
      )
    };
  items
  |> filterMap(item =>
       switch (item) {
       | String(_, name) => Some(name)
       | Option(
           _,
           String(_, name),
           [Relop(_, `Eq, Ident(_, "os"), String(_, "darwin"))],
         ) =>
         Some(name)
       | Option(
           _,
           String(_, _name),
           [Relop(_, `Eq, Ident(_, "os"), String(_, _))],
         ) =>
         None
       | Option(_, String(_, _name), [Ident(_, "preinstalled")]) => None
       | Option(
           _,
           String(_, name),
           [Pfxop(_, `Not, Ident(_, "preinstalled"))],
         ) =>
         Some(name)
       | _ =>
         print_endline(
           "Bad string list item arg " ++ OpamPrinter.value(item),
         );
         None;
       }
     );
};

let findArchive = (contents, _file_name) =>
  switch (findVariable("archive", contents)) {
  | Some(String(_, archive)) => Some(archive)
  | _ =>
    switch (findVariable("http", contents)) {
    | Some(String(_, archive)) => Some(archive)
    | _ =>
      switch (findVariable("src", contents)) {
      | Some(String(_, archive)) => Some(archive)
      | _ => None
      }
    }
  };

let parseUrlFile = ({file_contents, file_name}) =>
  switch (findArchive(file_contents, file_name)) {
  | None =>
    switch (findVariable("git", file_contents)) {
    | Some(String(_, git)) =>
      Types.PendingSource.GitSource(
        git,
        None /* TODO parse out commit info */,
      )
    | _ => failwith("Invalid url file - no archive: " ++ file_name)
    }
  | Some(archive) =>
    let checksum =
      switch (findVariable("checksum", file_contents)) {
      | Some(String(_, checksum)) => Some(checksum)
      | _ => None
      };
    Types.PendingSource.Archive(archive, checksum);
  };

let toDepSource = ((name, semver)) => {
  PackageJson.DependencyRequest.name,
  req: PackageJson.DependencyRequest.Opam(semver),
};

let getOpamFiles = (path: Path.t) => {
  open RunAsync.Syntax;
  let filesPath = Path.(path / "files");
  if%bind (Fs.isDir(filesPath)) {
    let collect = (files, filePath, _fileStats) =>
      switch (Path.relativize(~root=filesPath, filePath)) {
      | Some(relFilePath) =>
        let%bind fileData = Fs.readFile(filePath);
        return([(relFilePath, fileData), ...files]);
      | None => return(files)
      };
    Fs.fold(~init=[], ~f=collect, filesPath);
  } else {
    return([]);
  };
};

let getSubsts = opamvalue =>
  (
    switch (opamvalue) {
    | None => []
    | Some(List(_, items)) =>
      items
      |> List.map(item =>
           switch (item) {
           | String(_, text) => text
           | _ => failwith("Bad substs item")
           }
         )
    | Some(String(_, text)) => [text]
    | Some(other) =>
      failwith("Bad substs value " ++ OpamPrinter.value(other))
    }
  )
  |> List.map(filename => ["substs", filename ++ ".in"]);

let parseManifest = (info, {file_contents, file_name}) => {
  let (deps, buildDeps, devDeps) =
    processDeps(file_name, findVariable("depends", file_contents));
  let (depopts, _, _) =
    processDeps(file_name, findVariable("depopts", file_contents));
  let files =
    getOpamFiles(Path.(v(file_name) |> parent))
    |> RunAsync.runExn(~err="error crawling files");
  let patches = processStringList(findVariable("patches", file_contents));
  /** OPTIMIZE: only read the files when generating the lockfile */
  /* print_endline("Patches for " ++ file_name ++ " " ++ string_of_int(List.length(patches))); */
  let ocamlRequirement = {
    let req = findVariable("available", file_contents);
    let req = Option.map(~f=OpamAvailable.getOCamlVersion, req);
    Option.orDefault(~default=GenericVersion.Any, req);
  };
  /* We just don't support anything before 4.2.3 */
  let ourMinimumOcamlVersion = NpmVersion.parseConcrete("4.02.3");
  let isAVersionWeSupport =
    !
      GenericVersion.isTooLarge(
        NpmVersion.compare,
        ocamlRequirement,
        ourMinimumOcamlVersion,
      );
  let isAvailable = {
    let isAvailable = {
      let v = findVariable("available", file_contents);
      let v = Option.map(~f=OpamAvailable.getAvailability, v);
      Option.orDefault(~default=true, v);
    };
    isAVersionWeSupport && isAvailable;
  };

  let (ocamlDep, substDep, esyInstallerDep) = {
    open PackageJson.DependencyRequest;
    let ocamlDep = {
      name: "ocaml",
      req:
        Npm(
          And(
            GenericVersion.AtLeast(ourMinimumOcamlVersion),
            ocamlRequirement,
          ),
        ),
    };
    let substDep = {name: "@esy-ocaml/substs", req: Npm(GenericVersion.Any)};
    let esyInstallerDep = {
      name: "@esy-ocaml/esy-installer",
      req: Npm(GenericVersion.Any),
    };
    (ocamlDep, substDep, esyInstallerDep);
  };

  {
    fileName: file_name,
    build:
      getSubsts(findVariable("substs", file_contents))
      @ processCommandList(info, findVariable("build", file_contents))
      @ [["sh", "-c", "(esy-installer || true)"]],
    install:
      processCommandList(info, findVariable("install", file_contents)),
    patches,
    files,
    dependencies:
      [ocamlDep, substDep, esyInstallerDep]
      @ (deps |> List.map(toDepSource))
      @ (buildDeps |> List.map(toDepSource)),
    buildDependencies: PackageJson.Dependencies.empty,
    devDependencies: devDeps |> List.map(toDepSource),
    peerDependencies: [], /* TODO peer deps */
    optDependencies: depopts |> List.map(toDepSource),
    available: isAvailable, /* TODO */
    source: Types.PendingSource.NoSource,
    exportedEnv: [],
  };
};

let getSource = ({source, _}) => source;

let commandListToJson = e =>
  e |> List.map(items => `List(List.map(item => `String(item), items)));

let toPackageJson = (manifest, name, version) => {
  let exportedEnv =
    PackageJson.ExportedEnv.[
      {
        name: cleanEnvName(withoutScope(name)) ++ "_version",
        value: Solution.Version.toNpmVersion(version),
        scope: `Global,
      },
      {
        name: cleanEnvName(withoutScope(name)) ++ "_installed",
        value: "true",
        scope: `Global,
      },
      {
        name: cleanEnvName(withoutScope(name)) ++ "_enable",
        value: "enable",
        scope: `Global,
      },
      ...manifest.exportedEnv,
    ];

  (
    /* let manifest = getManifest(opamOverrides, (filename, "", withoutScope(name), switch version {
       | `Opam(t) => t
       | _ => failwith("unexpected opam version")
       })); */
    `Assoc([
      ("name", `String(name)),
      ("version", `String(Solution.Version.toNpmVersion(version))),
      (
        "esy",
        `Assoc([
          ("build", `List(commandListToJson(manifest.build))),
          ("install", `List(commandListToJson(manifest.install))),
          ("buildsInSource", `Bool(true)),
          ("exportedEnv", PackageJson.ExportedEnv.to_yojson(exportedEnv)),
        ]),
        /* ("buildsInSource", "_build") */
      ),
      (
        "_resolved",
        `String(
          Types.resolvedPrefix
          ++ name
          ++ "--"
          ++ Solution.Version.toString(version),
        ),
      ),
      (
        "peerDependencies",
        `Assoc([
          ("ocaml", `String("*")) /* HACK probably get this somewhere */,
        ]),
      ),
      (
        "optDependencies",
        `Assoc(
          manifest.optDependencies
          |> List.map(({PackageJson.DependencyRequest.name, _}) =>
               (name, `String("*"))
             ),
        ),
      ),
      (
        "dependencies",
        `Assoc(
          (
            manifest.dependencies
            |> List.map(({PackageJson.DependencyRequest.name, _}) =>
                 (name, `String("*"))
               )
          )
          @ (
            manifest.buildDependencies
            |> List.map(({PackageJson.DependencyRequest.name, _}) =>
                 (name, `String("*"))
               )
          ),
        ),
      ),
    ]),
    manifest.files,
    manifest.patches,
  );
};

let getDependenciesInfo = manifest => {
  PackageJson.DependenciesInfo.devDependencies: manifest.devDependencies,
  buildDependencies: manifest.buildDependencies,
  dependencies: manifest.dependencies,
};
