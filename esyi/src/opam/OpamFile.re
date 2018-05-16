
open Shared;
open OpamParserTypes;
open OpamOverrides.Infix;

let expectSuccess = (msg, v) => if (v) { () } else { failwith(msg) };

type manifest = {
  fileName: string,
  build: list(list(string)),
  install: list(list(string)),
  patches: list(string), /* these should be absolute */
  files: list((string, string)), /* relname, sourcetext */
  deps: list(Types.dep),
  buildDeps: list(Types.dep),
  devDeps: list(Types.dep),
  peerDeps: list(Types.dep),
  optDependencies: list(Types.dep),
  available: bool,
  /* TODO optDependencies (depopts) */
  source: Types.PendingSource.t,
  exportedEnv: list((string, (string, string))),
};

type thinManifest = (string, string, string, Shared.Types.opamConcrete);

let rec findVariable = (name, items) => switch items {
| [] => None
| [Variable(_, n, v), ..._] when n == name => Some(v)
| [_, ...rest] => findVariable(name, rest)
};

let opName = op => switch op {
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
    failwith("Opam name not prefixed: " ++ fullName)
  };
  String.sub(fullName, ln, String.length(fullName) - ln);
};

let toDep = opamvalue => {
  let (name, s, typ) = OpamVersion.toDep(opamvalue);
  (withScope(name), s, typ)
};

let processDeps = (fileName, deps) => {
  let deps = switch (deps) {
  | None => []
  | Some(List(_, items)) => items
  | Some(Group(_, items)) => items
  | Some(String(pos, value)) => [String(pos, value)]
  | Some(contents) => failwith("Can't handle the dependencies " ++ fileName ++ " " ++ OpamPrinter.value(contents))
  };

  List.fold_left(
    ((deps, buildDeps, devDeps), dep) => {
      let (name, dep, typ) = try(toDep(dep)) {
      | Failure(f) => {
        print_endline("Failed to process dep: " ++ f);
        print_endline(fileName);
        failwith("bad")
      }
      };
      switch typ {
      | `Link => ([(name, dep), ...deps], buildDeps, devDeps)
      | `Build => (deps, [(name, dep), ...buildDeps], devDeps)
      | `Test => (deps, buildDeps, [(name, dep), ...devDeps])
      }
    },
    ([], [], []),
    deps
  );
};

let filterMap = (fn, items) => {
  List.map(fn, items) |> List.filter(x => x != None) |> List.map(x => switch (x) { | Some(x) => x | None => assert(false)})
};

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

[@test [
  ((Str.regexp("a\\(.\\)"), String.uppercase_ascii, "applae"), "PplE"),
  ((Str.regexp("A\\(.\\)"), String.lowercase_ascii, "HANDS"), "HnDS"),
]]
let replaceGroupWithTransform = (rx, transform, string) => {
  Str.global_substitute(rx, s => transform(Str.matched_group(1, s)), string)
};

[@test [
  ((("awesome", Shared.Types.Alpha("", None)), "--%{fmt:enable}%-fmt"), "--${fmt_enable:-disable}-fmt")
]]
let replaceVariables = (info, string) => {
  let string = string
    |> replaceGroupWithTransform(Str.regexp("%{\\([^}]+\\):installed}%"), name => "${" ++ cleanEnvName(name) ++ "_installed:-false}")
    |> replaceGroupWithTransform(Str.regexp("%{\\([^}]+\\):enable}%"), name => "${" ++ cleanEnvName(name) ++ "_enable:-disable}")
    |> replaceGroupWithTransform(Str.regexp("%{\\([^}]+\\):version}%"), name => "${" ++ cleanEnvName(name) ++ "_version}")
    |> replaceGroupWithTransform(Str.regexp("%{\\([^}]+\\):bin}%"), name => "${" ++ cleanEnvName(name) ++ ".bin}")
    |> replaceGroupWithTransform(Str.regexp("%{\\([^}]+\\):share}%"), name => "${" ++ cleanEnvName(name) ++ ".share}")
    |> replaceGroupWithTransform(Str.regexp("%{\\([^}]+\\):lib}%"), name => "${" ++ cleanEnvName(name) ++ ".lib}")
  ;
  List.fold_left(
    (string, (name, res)) => {
      Str.global_replace(
        Str.regexp_string("%{" ++ name ++ "}%"),
        res,
        string
      )
    },
    string,
    variables(info)
  )
};

[@test [
  ({|"install" {!preinstalled}|}, Some("install")),
]]
[@test.call (string) => processCommandItem(("something", Alpha("a", None)), OpamParser.value_from_string(string, "wat"))]
let processCommandItem = (info, item) => {
  switch item {
  | String(_, name) => Some(replaceVariables(info, name))
  | Ident(_, ident) => {
    switch (List.assoc_opt(ident, variables(info))) {
    | Some(string) => Some(string)
    | None => {
      print_endline("⚠️ Missing vbl " ++ ident);
      None
    }
    }
  };
  | Option(_, _, [Ident(_, "preinstalled")]) => {
    /** Skipping preinstalled */
    None
  }
  | Option(_, _, [String(_, something)]) => {
    /* String options like "%{react:installed}%" are not currently supported */
    None
  }
  | Option(_, String(_, name), [Pfxop(_, `Not, Ident(_, "preinstalled"))]) => {
    /** Not skipping not preinstalled */
    Some(replaceVariables(info, name))
  }
  | _ => {
    /** TODO handle  "--%{text:enable}%-text" {"%{react:installed}%"} correctly */
    print_endline("Bad build arg " ++ OpamPrinter.value(item));
    None
  }
  };
};

let processCommand = (info, items) => {
  items |> filterMap(processCommandItem(info))
};

/** TODO handle optional build things */
let processCommandList = (info, item) => {
  switch(item) {
  | None => []
  | Some(List(_, items))
  | Some(Group(_, items)) => {
    switch items {
    | [String(_) | Ident(_), ...rest] => {
      [items |> processCommand(info)]
    }

    | _ =>
    items |> filterMap(item => {
      switch item {
      | List(_, items) => {
        Some(processCommand(info, items))
      }
      | Option(_, List(_, items), _) => {
        Some(processCommand(info, items))
      }
      | _ => {
        print_endline("Skipping a non-list build thing " ++ OpamPrinter.value(item));
        None
      }
      }
    });
    }

  }

  | Some(Ident(_, ident)) => {
    switch (List.assoc_opt(ident, variables(info))) {
    | Some(string) => [[string]]
    | None => {
      print_endline("⚠️ Missing vbl " ++ ident);
      []
    }
    }

  }
  | Some(item) => failwith("Unexpected type for a command list: " ++ OpamPrinter.value(item))
  };
};

/** TODO handle "patch-ocsigen-lwt-101.diff" {os = "darwin"} correctly */
[@test [
  ({|["patch-ocsigen-lwt-101.diff" {os = "darwin"}]|}, ["patch-ocsigen-lwt-101.diff"]),
  ({|["openbsd.diff" {os = "openbsd"}]|}, []),
]]
[@test.call (string) => processStringList(Some(OpamParser.value_from_string(string, "wat")))]
[@test.print (fmt, x) => Format.fprintf(fmt, "%s", String.concat(", ", x))]
let processStringList = item => {
  let items = switch(item) {
  | None => []
  | Some(List(_, items))
  | Some(Group(_, items)) => items
  | Some(item) => failwith("Unexpected type for a string list: " ++ OpamPrinter.value(item))
  };
  items |> filterMap(item => {
    switch item {
      | String(_, name) => Some(name)
      | Option(_, String(_, name), [Relop(_, `Eq, Ident(_, "os"), String(_, "darwin"))]) => Some(name)
      | Option(_, String(_, name), [Relop(_, `Eq, Ident(_, "os"), String(_, _))]) => None
      | Option(_, String(_, name), [Ident(_, "preinstalled")]) => None
      | Option(_, String(_, name), [Pfxop(_, `Not, Ident(_, "preinstalled"))]) => Some(name)
      | _ => {
        print_endline("Bad string list item arg " ++ OpamPrinter.value(item));
        None
      }
    }
  });
};

let findArchive = (contents, file_name) => {
  switch (findVariable("archive", contents)) {
  | Some(String(_, archive)) => Some(archive)
  | _ => {
    switch (findVariable("http", contents)) {
    | Some(String(_, archive)) => Some(archive)
    | _ =>
    switch (findVariable("src", contents)) {
    | Some(String(_, archive)) => Some(archive)
    | _ => None
    }
  }
  }
  }
};

let parseUrlFile = ({file_contents, file_name}) => {
  switch (findArchive(file_contents, file_name)) {
  | None => {
      switch (findVariable("git", file_contents)) {
      | Some(String(_, git)) => Types.PendingSource.GitSource(git, None /* TODO parse out commit info */)
      | _ => failwith("Invalid url file - no archive: " ++ file_name)
      }
  }
  | Some(archive) => {
    let checksum = switch (findVariable("checksum", file_contents)) {
    | Some(String(_, checksum)) => Some(checksum)
    | _ => None
    };
    Types.PendingSource.Archive(archive, checksum)
  }
  }
};

let toDepSource = ((name, semver)) => (name, Types.Opam(semver));

let getOpamFiles = (opam_name) => {
  let dir = Filename.concat(Filename.dirname(opam_name), "files");
  if (Files.isDirectory(dir)) {
    let collected = ref([]);
    Files.crawl(dir, (rel, full) => {
      collected := [(rel, Files.readFile(full) |! "opam file unreadable"), ...collected^]
    });
    collected^;
  } else {
    []
  }
};

let getSubsts = opamvalue => (switch opamvalue {
| None => []
| Some(List(_, items)) => items |> List.map(item => switch item { | String(_, text) => text | _ => failwith("Bad substs item")})
| Some(String(_, text)) => [text]
| Some(other) => failwith("Bad substs value " ++ OpamPrinter.value(other))
}) |> List.map(filename => ["substs", filename ++ ".in"]);

let parseManifest = (info, {file_contents, file_name}) => {
  /* let baseDir = Filename.dirname(file_name); */
  /* NOTE: buildDeps are not actually buildDeps as we think of them, because they can also have runtime components. */
  let (deps, buildDeps, devDeps) = processDeps(file_name, findVariable("depends", file_contents));
  let (depopts, _, _) = processDeps(file_name, findVariable("depopts", file_contents));
  let files = getOpamFiles(file_name);
  let patches = processStringList(findVariable("patches", file_contents));
  /** OPTIMIZE: only read the files when generating the lockfile */
  /* print_endline("Patches for " ++ file_name ++ " " ++ string_of_int(List.length(patches))); */
  let ocamlRequirement = findVariable("available", file_contents) |?>> OpamAvailable.getOCamlVersion |? GenericVersion.Any;
  /* We just don't support anything before 4.2.3 */
  let ourMinimumOcamlVersion = Npm.NpmVersion.parseConcrete("4.02.3");
  let isAVersionWeSupport = !Shared.GenericVersion.isTooLarge(Npm.NpmVersion.compare, ocamlRequirement, ourMinimumOcamlVersion);
  let isAvailable = isAVersionWeSupport && findVariable("available", file_contents) |?>> OpamAvailable.getAvailability |? true;
  /* Npm.NpmVersion.matches(ocamlRequirement, ourMinimumOcamlVersion); */
  {
    fileName: file_name,
    build:
    getSubsts(findVariable("substs", file_contents)) @
    processCommandList(info, findVariable("build", file_contents)) @ [
      ["sh", "-c", "(esy-installer || true)"]
    ],
    install: processCommandList(info, findVariable("install", file_contents)),
    patches,
    files,
    deps: ((deps @ buildDeps) |> List.map(toDepSource)) @ [
      /* HACK? Not sure where/when this should be specified */
      ("@esy-ocaml/substs", Npm(GenericVersion.Any)),
      ("@esy-ocaml/esy-installer", Npm(GenericVersion.Any)),
      ("ocaml", Npm(And(GenericVersion.AtLeast(ourMinimumOcamlVersion), ocamlRequirement))),
    ],
    buildDeps: [],
    /* buildDeps |> List.map(toDepSource), */
    devDeps: devDeps |> List.map(toDepSource),
    peerDeps: [], /* TODO peer deps */
    optDependencies: depopts |> List.map(toDepSource),
    available: isAvailable, /* TODO */
    source: Types.PendingSource.NoSource,
    exportedEnv: [],
  };
};

let parseDepVersion = ((name, version)) => {
  Npm.PackageJson.parseNpmSource((name, version))
};

module StrSet = Set.Make(String);
let assignAssoc = (target, override) => {
  let replacing = List.fold_left(
    ((set, (name, _)) => StrSet.add(name, set)),
    StrSet.empty,
    override
  );
  List.filter(((name, _)) => !StrSet.mem(name, replacing), target) @ override
};

module O = OpamOverrides;
let mergeOverride = (manifest, override) => {
  let source = override.O.opam |?> (opam => opam.O.source) |? manifest.source;
  {
    ...manifest,
    build: override.O.build |? manifest.build,
    install: override.O.install |? manifest.install,
    deps: assignAssoc(manifest.deps, override.O.dependencies |> List.map(parseDepVersion)),
    peerDeps: assignAssoc(manifest.peerDeps, override.O.peerDependencies |> List.map(parseDepVersion)),
    files: manifest.files @ (override.O.opam |?>> (o => o.O.files) |? []),
    source: source,
    exportedEnv: override.O.exportedEnv
  }
};

let getManifest = (opamOverrides, (opam, url, name, version)) => {
  let manifest = {
    ...parseManifest((name, version), OpamParser.file(opam)),
    source: Files.exists(url) ? parseUrlFile(OpamParser.file(url)) : Types.PendingSource.NoSource
  };
  switch (OpamOverrides.findApplicableOverride(opamOverrides, name, version)) {
  | None => {
    /* print_endline("No override for " ++ name ++ " " ++ VersionNumber.viewVersionNumber(version)); */
    manifest
  }
  | Some(override) => {
    /* print_endline("!! Found override for " ++ name); */
    let m = mergeOverride(manifest, override);
    m
  }
  }
};

let getSource = ({source}) => source;

let process = ({deps, buildDeps, devDeps}) => {
  {Types.runtime: deps @ buildDeps, build: [], dev: devDeps, npm: []}
  /* (deps, buildDeps, devDeps) */
};

let commandListToJson = e => e |> List.map(items => `List(List.map(item => `String(item), items)));

let toPackageJson = (manifest, name, version) => {
  /* let manifest = getManifest(opamOverrides, (filename, "", withoutScope(name), switch version {
  | `Opam(t) => t
  | _ => failwith("unexpected opam version")
  })); */

  (`Assoc([
    ("name", `String(name)),
    ("version", `String(Lockfile.plainVersionNumber(version))),
    ("esy", `Assoc([
      ("build", `List(commandListToJson(manifest.build))),
      ("install", `List(commandListToJson(manifest.install))),
      ("buildsInSource", `Bool(true)),
      ("exportedEnv", `Assoc(
        ([
          (cleanEnvName(withoutScope(name)) ++ "_version", (Lockfile.plainVersionNumber(version), "global")),
          (cleanEnvName(withoutScope(name)) ++ "_installed", ("true", "global")),
          (cleanEnvName(withoutScope(name)) ++ "_enable", ("enable", "global")),
        ] @
        manifest.exportedEnv)
        |> List.map(((name, (val_, scope))) => (
          name,
          `Assoc([
            ("val", `String(val_)),
            ("scope", `String(scope))
          ])
        ))
      ))
      /* ("buildsInSource", "_build") */
    ])),
    ("_resolved", `String(Types.resolvedPrefix ++ name ++ "--" ++ Lockfile.viewRealVersion(version))),
    ("peerDependencies", `Assoc([
      ("ocaml", `String("*")) /* HACK probably get this somewhere */
    ])),
    ("optDependencies", `Assoc(
      (manifest.optDependencies |> List.map(((name, _)) => (name, `String("*"))))
    )),
    ("dependencies", `Assoc(
      (manifest.deps |> List.map(((name, _)) => (name, `String("*"))))
      @
      (manifest.buildDeps |> List.map(((name, _)) => (name, `String("*"))))
    ))
  ]), manifest.files, manifest.patches)
};
