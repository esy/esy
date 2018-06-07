open OpamParserTypes;

module Version = OpamVersion.Version;
module Formula = OpamVersion.Formula;

module PackageName: {
  type t;

  let toNpm: t => string;
  let ofNpm: string => Run.t(t);
  let ofNpmExn: string => t;

  let toString: t => string;
  let ofString: string => t;
} = {
  module String = Astring.String;

  type t = string;

  let toString = name => name;
  let ofString = name => name;

  let toNpm = name => "@opam/" ++ name;
  let ofNpm = name =>
    switch (String.cut(~sep="/", name)) {
    | Some(("@opam", name)) => Ok(name)
    | Some(_)
    | None =>
      let msg = Printf.sprintf("%s: missing @opam/ prefix", name);
      Run.error(msg);
    };
  let ofNpmExn = name =>
    switch (Run.toResult(ofNpm(name))) {
    | Ok(name) => name
    | Error(err) => raise(Invalid_argument(err))
    };
};

type manifest = {
  name: PackageName.t,
  version: Version.t,
  fileName: string,
  build: list(list(string)),
  install: list(list(string)),
  patches: list(string), /* these should be absolute */
  files: list((Path.t, string)), /* relname, sourcetext */
  dependencies: PackageInfo.Dependencies.t,
  buildDependencies: PackageInfo.Dependencies.t,
  devDependencies: PackageInfo.Dependencies.t,
  peerDependencies: PackageInfo.Dependencies.t,
  optDependencies: PackageInfo.Dependencies.t,
  available: bool,
  /* TODO optDependencies (depopts) */
  source: PackageInfo.Source.t,
  exportedEnv: PackageJson.ExportedEnv.t,
};

module ThinManifest = {
  type t = {
    name: PackageName.t,
    opamFile: Path.t,
    urlFile: Path.t,
    version: Version.t,
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

module ParseDeps = {
  open OpamVersion;

  let fromPrefix = (op, version) => {
    let v = Version.parseExn(version);
    switch (op) {
    | `Eq => Formula.EQ(v)
    | `Geq => Formula.GTE(v)
    | `Leq => Formula.LTE(v)
    | `Lt => Formula.LT(v)
    | `Gt => Formula.GT(v)
    | `Neq => failwith("Can't do neq in opam version constraints")
    };
  };

  let rec parseRange = opamvalue =>
    OpamParserTypes.(
      switch (opamvalue) {
      | Prefix_relop(_, op, String(_, version)) => fromPrefix(op, version)
      | Logop(_, `And, left, right) =>
        AND(parseRange(left), parseRange(right))
      | Logop(_, `Or, left, right) =>
        OR(parseRange(left), parseRange(right))
      | String(_, version) => EQ(OpamVersion.Version.parseExn(version))
      | Option(_, contents, options) =>
        print_endline(
          "Ignoring option: "
          ++ (
            options |> List.map(OpamPrinter.value) |> String.concat(" .. ")
          ),
        );
        parseRange(contents);
      | _y =>
        print_endline(
          "Unexpected option -- pretending its any "
          ++ OpamPrinter.value(opamvalue),
        );
        ANY;
      }
    );

  let rec toDep = opamvalue =>
    OpamParserTypes.(
      switch (opamvalue) {
      | String(_, name) => (name, Formula.ANY, `Link)
      | Option(_, String(_, name), [Ident(_, "build")]) => (
          name,
          ANY,
          `Build,
        )
      | Option(
          _,
          String(_, name),
          [Logop(_, `And, Ident(_, "build"), version)],
        ) => (
          name,
          parseRange(version),
          `Build,
        )
      | Option(_, String(_, name), [Ident(_, "test")]) => (
          name,
          ANY,
          `Test,
        )
      | Option(
          _,
          String(_, name),
          [Logop(_, `And, Ident(_, "test"), version)],
        ) => (
          name,
          parseRange(version),
          `Test,
        )
      | Group(_, [Logop(_, `Or, String(_, "base-no-ppx"), otherThing)]) =>
        /* yep we allow ppxs */
        toDep(otherThing)
      | Group(_, [Logop(_, `Or, String(_, one), String(_, two))]) =>
        print_endline(
          "Arbitrarily choosing the second of two options: "
          ++ one
          ++ " and "
          ++ two,
        );
        (two, ANY, `Link);
      | Group(_, [Logop(_, `Or, first, second)]) =>
        print_endline(
          "Arbitrarily choosing the first of two options: "
          ++ OpamPrinter.value(first)
          ++ " and "
          ++ OpamPrinter.value(second),
        );
        toDep(first);
      | Option(_, String(_, name), [option]) => (
          name,
          parseRange(option),
          `Link,
        )
      | _ =>
        failwith(
          "Can't parse this opam dep " ++ OpamPrinter.value(opamvalue),
        )
      }
    );

  let parse = opamvalue => {
    let (name, s, typ) = toDep(opamvalue);
    (name, s, typ);
  };
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
        try (ParseDeps.parse(dep)) {
        | Failure(f) =>
          print_endline("Failed to process dep: " ++ f);
          print_endline(fileName);
          failwith("bad");
        };
      switch (typ) {
      | `Link => (
          [(PackageName.ofString(name), dep), ...deps],
          buildDeps,
          devDeps,
        )
      | `Build => (
          deps,
          [(PackageName.ofString(name), dep), ...buildDeps],
          devDeps,
        )
      | `Test => (
          deps,
          buildDeps,
          [(PackageName.ofString(name), dep), ...devDeps],
        )
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
let variables = ((name: PackageName.t, version)) => [
  ("jobs", "4"),
  ("make", "make"),
  ("ocaml-native", "true"),
  ("ocaml-native-dynlink", "true"),
  ("bin", "$cur__install/bin"),
  ("lib", "$cur__install/lib"),
  ("man", "$cur__install/man"),
  ("share", "$cur__install/share"),
  ("pinned", "false"),
  ("name", PackageName.toString(name)),
  ("version", Version.toString(version)),
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
      /* TODO parse out commit info */
      PackageInfo.SourceSpec.Git(git, None)
    | _ => failwith("Invalid url file - no archive: " ++ file_name)
    }
  | Some(archive) =>
    let checksum =
      switch (findVariable("checksum", file_contents)) {
      | Some(String(_, checksum)) => Some(checksum)
      | _ => None
      };
    PackageInfo.SourceSpec.Archive(archive, checksum);
  };

let toDepSource = ((name, formula)) => {
  let name = PackageName.toNpm(name);
  PackageInfo.Req.ofSpec(~name, ~spec=PackageInfo.VersionSpec.Opam(formula));
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

let parseManifest =
    (info: (PackageName.t, Version.t), {file_contents, file_name}) => {
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
    Option.orDefault(~default=NpmVersion.Formula.ANY, req);
  };
  /* We just don't support anything before 4.2.3 */
  let ourMinimumOcamlVersion = NpmVersion.Version.parseExn("4.2.3");
  let isAVersionWeSupport =
    ! NpmVersion.Formula.isTooLarge(ocamlRequirement, ourMinimumOcamlVersion);
  let isAvailable = {
    let isAvailable = {
      let v = findVariable("available", file_contents);
      let v = Option.map(~f=OpamAvailable.getAvailability, v);
      Option.orDefault(~default=true, v);
    };
    isAVersionWeSupport && isAvailable;
  };

  let (ocamlDep, substDep, esyInstallerDep) = {
    let ocamlDep =
      PackageInfo.Req.ofSpec(
        ~name="ocaml",
        ~spec=
          Npm(
            NpmVersion.Formula.AND(
              NpmVersion.Formula.GTE(ourMinimumOcamlVersion),
              ocamlRequirement,
            ),
          ),
      );
    let substDep =
      PackageInfo.Req.ofSpec(
        ~name="@esy-ocaml/substs",
        ~spec=Npm(NpmVersion.Formula.ANY),
      );
    let esyInstallerDep =
      PackageInfo.Req.ofSpec(
        ~name="@esy-ocaml/esy-installer",
        ~spec=Npm(NpmVersion.Formula.ANY),
      );
    (ocamlDep, substDep, esyInstallerDep);
  };

  let (name, version) = info;
  {
    name,
    version,
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
    buildDependencies: PackageInfo.Dependencies.empty,
    devDependencies: devDeps |> List.map(toDepSource),
    peerDependencies: [], /* TODO peer deps */
    optDependencies: depopts |> List.map(toDepSource),
    available: isAvailable, /* TODO */
    source: PackageInfo.Source.NoSource,
    exportedEnv: [],
  };
};

let source = ({source, _}) => source;

let commandListToJson = e =>
  e |> List.map(items => `List(List.map(item => `String(item), items)));

let toPackageJson = (manifest, version) => {
  let npmName = PackageName.toNpm(manifest.name);
  let opamName = PackageName.toString(manifest.name);
  let exportedEnv =
    PackageJson.ExportedEnv.[
      {
        name: cleanEnvName(opamName) ++ "_version",
        value: PackageInfo.Version.toNpmVersion(version),
        scope: `Global,
      },
      {
        name: cleanEnvName(opamName) ++ "_installed",
        value: "true",
        scope: `Global,
      },
      {
        name: cleanEnvName(opamName) ++ "_enable",
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
      ("name", `String(npmName)),
      ("version", `String(PackageInfo.Version.toNpmVersion(version))),
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
          Config.resolvedPrefix
          ++ npmName
          ++ "--"
          ++ PackageInfo.Version.toString(version),
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
          |> List.map(req => (PackageInfo.Req.name(req), `String("*"))),
        ),
      ),
      (
        "dependencies",
        `Assoc(
          (
            manifest.dependencies
            |> List.map(req => (PackageInfo.Req.name(req), `String("*")))
          )
          @ (
            manifest.buildDependencies
            |> List.map(req => (PackageInfo.Req.name(req), `String("*")))
          ),
        ),
      ),
    ]),
    manifest.files,
    manifest.patches,
  );
};

let name = manifest => PackageName.toNpm(manifest.name);
let version = manifest => manifest.version;

let dependencies = manifest => {
  PackageInfo.DependenciesInfo.devDependencies: manifest.devDependencies,
  buildDependencies: manifest.buildDependencies,
  dependencies: manifest.dependencies,
};
