module Dependencies = PackageInfo.Dependencies

module PackageName : sig
  type t

  val toNpm : t -> string
  val ofNpm : string -> t Run.t
  val ofNpmExn : string -> t

  val toString : t -> string
  val ofString : string -> t

  val compare : t -> t -> int
  val equal : t -> t -> bool

end = struct
  module String = Astring.String
  type t = string

  let toNpm name = "@opam/" ^ name

  let ofNpm name =
    match String.cut ~sep:"/" name with
    | Some ("@opam", name) -> Ok name
    | Some _
    | None ->
      let msg = Printf.sprintf "%s: missing @opam/ prefix" name in
      Run.error msg

  let ofNpmExn name =
    match Run.toResult (ofNpm name) with
    | Ok name -> name
    | Error err -> raise (Invalid_argument err)

  let toString name = name
  let ofString name = name

  let compare = String.compare
  let equal = String.equal
end

type t = {
  name: PackageName.t;
  version: OpamVersion.Version.t;
  fileName: string;
  build: string list list;
  install: string list list;
  patches: string list;
  files: (Path.t * string) list;
  dependencies: Dependencies.t;
  buildDependencies: Dependencies.t;
  devDependencies: Dependencies.t;
  peerDependencies: Dependencies.t;
  optDependencies: Dependencies.t;
  available: [ | `IsNotAvailable  | `Ok ] ;
  source: PackageInfo.Source.t;
  exportedEnv: PackageJson.ExportedEnv.t
}

module ParseDeps = struct
  module V = OpamVersion.Version
  module F = OpamVersion.Formula
  module C = OpamVersion.Formula.Constraint

  let unit c = F.OR [F.AND [c]]

  let parsePrefixRelop op version =
    let v = V.parseExn version in
    match op with
    | `Eq -> unit (C.EQ v)
    | `Geq -> unit (C.GTE v)
    | `Leq -> unit (C.LTE v)
    | `Lt -> unit (C.LT v)
    | `Gt -> unit (C.GT v)
    | `Neq -> F.OR [F.AND [C.LT v]; F.AND [C.GT v]]

  let rec parseRange filename opamvalue =
    let open OpamParserTypes in
    let open Option.Syntax in
    match opamvalue with
    | Ident (_, "doc")
    | Ident (_, "test") -> None

    | Prefix_relop (_, op, (String (_, version))) -> return (parsePrefixRelop op version)

    | Logop (_, `And, syn, Ident (_, "build"))
    | Logop (_, `And, Ident (_, "build"), syn) -> parseRange filename syn

    | Logop (_, `And, left, right) ->
      let%bind left = parseRange filename left in
      let%bind right = parseRange filename right in
      return (F.DNF.conj left right)

    | Logop (_, `Or, left, right) -> begin
      match parseRange filename left, parseRange filename right with
      | Some left, Some right -> return (F.DNF.disj left right)
      | Some left, None -> return left
      | None, Some right -> return right
      | None, None -> None
      end

    | String (_, version) -> return (unit (C.EQ (OpamVersion.Version.parseExn version)))

    | Option (_, contents, options) ->
      print_endline ("Ignoring option: " ^
            (options |> List.map ~f:OpamPrinter.value |>
                String.concat " .. "));
      parseRange filename contents
    | _y ->
        (Printf.printf
            (("OpamFile: %s: Unexpected option -- pretending its any: %s\n")
            [@reason.raw_literal
              "OpamFile: %s: Unexpected option -- pretending its any: %s\\n"])
            filename (OpamPrinter.value opamvalue);
          return (unit C.ANY))

  let rec toDep filename opamvalue =
    let open OpamParserTypes in
    let open Option.Syntax in
    match opamvalue with
    | String (_, name) ->
      Some (name, unit C.ANY, `Link)

    | Option (_, String (_, name), Ident (_, "build")::[]) ->
      Some (name, unit C.ANY, `Build)
    | Option (_, String (_, name), Ident (_, "test")::[]) ->
      Some (name, unit C.ANY, `Test)

    | Option (_, String (_, name), Logop (_, `And, Ident (_, "build"), version)::[]) ->
      let%bind spec = parseRange filename version in
      Some (name, spec, `Build)
    | Option (_, String (_, name), Logop (_, `And, Ident (_, "test"), version)::[]) ->
      let%bind spec = parseRange filename version in
      Some (name, spec, `Test)

    | Group (_, Logop (_, `Or, String (_, "base-no-ppx"), otherThing)::[]) ->
      toDep filename otherThing

    | Group (_, Logop (_, `Or, String (_, one), String (_, two))::[]) ->
      Printf.printf
        "Arbitrarily choosing the second of two options: %s and %s"
        one two;
      Some (two, unit C.ANY, `Link)

    | Group (_, (Logop (_, `Or, one, two))::[]) ->
      Printf.printf
        "Arbitrarily choosing the first of two options: %s and %s"
        (OpamPrinter.value one) (OpamPrinter.value two);
        toDep filename one

    | Option (_, String (_, name), option::[]) ->
      let%bind spec = parseRange filename option in
      Some (name, spec, `Link)

    | _ ->
      let msg =
        Printf.sprintf
          "Can't parse this opam dep %s"
          (OpamPrinter.value opamvalue)
      in
      failwith msg
end

let processDeps filename deps =
  let open OpamParserTypes in
  let deps =
    match deps with
    | None -> []
    | Some (List (_, items)) -> items
    | Some (Group (_, items)) -> items
    | Some (String (pos, value)) -> [String (pos, value)]
    | Some contents ->
      let msg = Printf.sprintf
        "Can't handle dependencies at %s: %s"
        filename (OpamPrinter.value contents)
      in failwith msg
  in
  let f (deps, buildDeps, devDeps) dep =
    match ParseDeps.toDep filename dep with
    | Some (name, formula, `Link) ->
      let name = PackageName.(name |> ofString |> toNpm) in
      let spec = PackageInfo.VersionSpec.Opam formula in
      let req = PackageInfo.Req.ofSpec ~name ~spec in
      (req::deps, buildDeps, devDeps)
    | Some (name, formula, `Build) ->
      let name = PackageName.(name |> ofString |> toNpm) in
      let spec = PackageInfo.VersionSpec.Opam formula in
      let req = PackageInfo.Req.ofSpec ~name ~spec in
      (deps, req::buildDeps, devDeps)
    | Some (name, formula, `Test) ->
      let name = PackageName.(name |> ofString |> toNpm) in
      let spec = PackageInfo.VersionSpec.Opam formula in
      let req = PackageInfo.Req.ofSpec ~name ~spec in
      (deps, buildDeps, req::devDeps)
    | None -> (deps, buildDeps, devDeps)
    | exception Failure msg ->
      let msg = Printf.sprintf
        "Can't handle dependencies at %s: %s"
        filename msg
      in failwith msg
  in
  List.fold_left ~f ~init:([], [], []) deps

let processCommandItem filename item =
  let open OpamParserTypes in
  match item with
  | String (_, value) -> Some value
  | Ident (_, ident) -> Some ("%{" ^ ident ^ "}%")
  | Option (_, _, Ident (_, "preinstalled")::[]) -> None
  | Option (_, _, String (_, _something)::[]) -> None
  | Option (_, String (_, name), Pfxop (_, `Not, (Ident (_, ("preinstalled"))))::[]) -> Some name
  | _ ->
    Printf.printf
      "opam: %s\nmessage: invalid command item\nvalue: %s\n"
      filename (OpamPrinter.value item);
    None

let processCommand filename items =
  items |> List.map ~f:(processCommandItem filename) |> List.filterNone

let processCommandList filename item =
  let open OpamParserTypes in
  match item with
  | None -> []
  | Some (List (_, items))
  | Some (Group (_, items)) -> begin
    match items with
      | (String _ | Ident _)::_rest -> [processCommand filename items]
      | items ->
        let f item =
          match item with
          | List (_, items) -> Some (processCommand filename items)
          | Option (_, List (_, items), _) -> Some (processCommand filename items)
          | _ ->
            Printf.printf "Skipping a non-list build thing %s" (OpamPrinter.value item);
            None
        in
        items
        |> List.map ~f
        |> List.filterNone
    end
  | Some (Ident (_, ident)) -> [["%{" ^ ident ^ "}%"]]

  | Some item ->
    let msg =
      Printf.sprintf
        "Unexpected type for a command list: %s"
        (OpamPrinter.value item)
    in failwith msg

let parsePatches filename item =
  let open OpamParserTypes in
  let items =
    match item with
    | None -> []
    | Some (List (_, items))
    | Some (Group (_, items)) -> items

    | Some (String _ as item) -> [item]
    | Some item ->
      let msg =
        Printf.sprintf
          (("opam: %s\nerror: Unexpected type for a string list\nvalue: %s\n")
          [@reason.raw_literal
            "opam: %s\\nerror: Unexpected type for a string list\\nvalue: %s\\n"])
          filename (OpamPrinter.value item) in
      failwith msg
  in

  let f item =
    match item with
    | String (_, name) -> Some name
    | Option (_, String (_, name), Relop (_, `Eq, Ident (_, "os"), String (_, "darwin"))::[]) ->
      Some name
    | Option (_, String (_, _name), Relop (_, `Eq, Ident (_, "os"), String (_, _))::[]) -> None
    | Option (_, String (_, _name), Ident (_, "preinstalled")::[]) -> None
    | Option (_, String (_, name), Pfxop (_, `Not, Ident (_, "preinstalled"))::[]) -> Some name
    | _ ->
      Printf.printf
        "opam: %s\nwarning: Bad string list item arg\nvalue: %s\n"
        filename (OpamPrinter.value item);
      None
  in
  items |> List.map ~f |> List.filterNone

let rec findVariable name items =
  let open OpamParserTypes in
  match items with
  | [] -> None
  | Variable (_, n, v)::_ when n = name -> Some v
  | _::rest -> findVariable name rest

let findArchive contents _file_name =
  let open OpamParserTypes in
  match findVariable "archive" contents with
  | Some (String (_, archive)) ->
    Some archive
  | _ -> begin
    match findVariable "http" contents with
    | Some (String (_, archive)) -> Some archive
    | _ -> begin
      match findVariable "src" contents with
      | Some (String (_, archive)) -> Some archive
      | _ -> None
      end
    end

let getOpamFiles (path : Path.t) =
  let open RunAsync.Syntax in
  let filesPath = Path.(path / "files") in
  if%bind Fs.isDir filesPath
  then
    let collect files filePath _fileStats =
      match Path.relativize ~root:filesPath filePath with
      | Some relFilePath ->
        let%bind fileData = Fs.readFile filePath in
        return ((relFilePath, fileData)::files)
      | None -> return files
    in
    Fs.fold ~init:[] ~f:collect filesPath
  else return []

let getSubsts opamvalue =
  let open OpamParserTypes in
  let items =
    match opamvalue with
    | None -> []
    | Some (List (_, items)) ->
      let f item =
        match item with
        | String (_, text) -> text
        | _ -> failwith "Bad substs item"
      in
      List.map ~f items
    | Some (String (_, text)) -> [text]
    | Some other ->
        failwith ("Bad substs value " ^ (OpamPrinter.value other))
  in
  List.map ~f:(fun filename -> ["substs"; filename ^ ".in"]) items

let parse ~name ~version { OpamParserTypes. file_contents; file_name } =
  let (deps, buildDeps, devDeps) =
    processDeps file_name (findVariable "depends" file_contents)
  in
  let (depopts, _, _) =
    processDeps file_name (findVariable "depopts" file_contents)
  in
  let files =
    getOpamFiles Path.(v file_name |> parent)
    |> RunAsync.runExn ~err:"error crawling files"
  in
  let patches =
    parsePatches file_name (findVariable "patches" file_contents)
  in
  let ocamlRequirement =
    let req = findVariable "available" file_contents in
    let req = Option.map ~f:OpamAvailable.getOCamlVersion req in
    Option.orDefault ~default:NpmVersion.Formula.any req
  in
  let ourMinimumOcamlVersion = NpmVersion.Version.parseExn "4.2.3" in
  let isAvailable =
    let isAvailable =
      let v = findVariable "available" file_contents in
      let v = Option.map ~f:OpamAvailable.getAvailability v in
      Option.orDefault ~default:true v
    in
    if not isAvailable
    then `IsNotAvailable
    else `Ok
  in
  let (ocamlDep, substDep, esyInstallerDep) =
    let ocamlDep =
      PackageInfo.Req.ofSpec
        ~name:"ocaml"
        ~spec:(
          Npm NpmVersion.Formula.(DNF.conj
            ocamlRequirement
            (OR [AND [Constraint.GTE ourMinimumOcamlVersion]]))
          )
    in
    let substDep =
      PackageInfo.Req.ofSpec
        ~name:"@esy-ocaml/substs"
        ~spec:((Npm (NpmVersion.Formula.any))[@explicit_arity ])
    in
    let esyInstallerDep =
      PackageInfo.Req.ofSpec
        ~name:"@esy-ocaml/esy-installer"
        ~spec:(Npm NpmVersion.Formula.any)
    in
    (ocamlDep, substDep, esyInstallerDep)
  in

  let dependencies = Dependencies.(
      empty
      |> add ~req:ocamlDep
      |> add ~req:substDep
      |> add ~req:esyInstallerDep
      |> addMany ~reqs:deps
      |> addMany ~reqs:buildDeps
    )
  in
  let devDependencies = Dependencies.(empty |> addMany ~reqs:devDeps) in
  let optDependencies = Dependencies.(empty |> addMany ~reqs:depopts) in

  {
    name;
    version;
    fileName = file_name;
    build =
      getSubsts (findVariable "substs" file_contents)
      @ (processCommandList file_name (findVariable "build" file_contents))
      @ [["sh"; "-c"; "(esy-installer || true)";]];
    install =
      processCommandList file_name (findVariable "install" file_contents);
    patches;
    files;
    dependencies;
    devDependencies;
    optDependencies;
    buildDependencies = Dependencies.empty;
    peerDependencies = Dependencies.empty;
    available = isAvailable;
    source = PackageInfo.Source.NoSource;
    exportedEnv = []
  }

let commandListToJson =
  let f items = `List (List.map ~f:(fun item -> `String item) items) in
  List.map ~f

let toPackageJson manifest version =
  let npmName = PackageName.toNpm manifest.name in
  let exportedEnv = manifest.exportedEnv in
  let packageJson =
    `Assoc [
      "name", `String npmName;
      "version", `String (PackageInfo.Version.toNpmVersion version);
      "esy", `Assoc [
        "build", `List (commandListToJson manifest.build);
        "install", `List (commandListToJson manifest.install);
        "buildsInSource", `Bool true;
        "exportedEnv", PackageJson.ExportedEnv.to_yojson exportedEnv;
      ];
      "peerDependencies", Dependencies.to_yojson manifest.peerDependencies;
      "optDependencies", Dependencies.to_yojson manifest.optDependencies;
      "dependencies", Dependencies.to_yojson manifest.dependencies;
    ]
  in
  {
    PackageInfo.OpamInfo.packageJson = packageJson;
    files = (manifest.files);
    patches = (manifest.patches)
  }

module Url = struct
  let parse { OpamParserTypes. file_contents; file_name } =
    match findArchive file_contents file_name with
    | None -> begin
      match findVariable "git" file_contents with
      | Some (String (_, git)) -> PackageInfo.SourceSpec.Git (git, None)
      | _ ->
        failwith ("Invalid url file - no archive: " ^ file_name)
      end
    | Some archive ->
        let checksum =
          match findVariable "checksum" file_contents with
          | Some (String (_, checksum)) -> Some checksum
          | _ -> None
        in
        PackageInfo.SourceSpec.Archive (archive, checksum)
end
