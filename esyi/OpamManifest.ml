module Dependencies = Package.Dependencies

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

module Problem = struct
  type t = {
    value : OpamParserTypes.value option;
    message : string;
  }

  let make ?value message = {value; message;}
  let pp fmt pr =
    match pr.value with
    | Some value -> Fmt.pf fmt "@[<v>problem: %s@\nvalue: %s@]" pr.message (OpamPrinter.value value)
    | None -> Fmt.pf fmt "problem: %s" pr.message
end

type 'v parser = OpamParserTypes.opamfile -> ('v * Problem.t list, Problem.t) result

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
  source: Package.Source.t;
  exportedEnv: Package.ExportedEnv.t
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

  let rec parse ~emitWarning value =
    let open OpamParserTypes in

    let rec parseRange value =
      let open OpamParserTypes in
      let open Option.Syntax in
      match value with
      | Ident (_, "doc")
      | Ident (_, "test") -> None

      | Prefix_relop (_, op, (String (_, version))) ->
        return (parsePrefixRelop op version)

      | Logop (_, `And, syn, Ident (_, "build"))
      | Logop (_, `And, Ident (_, "build"), syn) -> parseRange syn

      | Logop (_, `And, left, right) ->
        let%bind left = parseRange left in
        let%bind right = parseRange right in
        return (F.DNF.conj left right)

      | Logop (_, `Or, left, right) -> begin
        match parseRange left, parseRange right with
        | Some left, Some right -> return (F.DNF.disj left right)
        | Some left, None -> return left
        | None, Some right -> return right
        | None, None -> None
        end

      | String (_, version) ->
        return (unit (C.EQ (OpamVersion.Version.parseExn version)))

      | Option (_, contents, _options) ->
        emitWarning ~value "unknown option value" ();
        parseRange contents
      | value ->
        emitWarning ~value "unknown value" ();
        return (unit C.ANY)
    in

    match value with
    | String (_, name) ->
      Ok (Some (name, unit C.ANY, `Link))

    | Option (_, String (_, name), Ident (_, "build")::[]) ->
      Ok (Some (name, unit C.ANY, `Build))
    | Option (_, String (_, name), Ident (_, "test")::[]) ->
      Ok (Some (name, unit C.ANY, `Test))

    | Option (_, String (_, name), Logop (_, `And, Ident (_, "build"), version)::[]) ->
      let deps =
        let open Option.Syntax in
        let%bind spec = parseRange version in
        Some (name, spec, `Build)
      in
      Ok deps
    | Option (_, String (_, name), Logop (_, `And, Ident (_, "test"), version)::[]) ->
      let deps =
        let open Option.Syntax in
        let%bind spec = parseRange version in
        Some (name, spec, `Test)
      in
      Ok deps

    | Group (_, Logop (_, `Or, String (_, "base-no-ppx"), otherThing)::[]) ->
      parse ~emitWarning otherThing

    | Group (_, Logop (_, `Or, String (_, _one), String (_, two))::[]) ->
      emitWarning
        ~value
        "Arbitrarily choosing the second of two options"
        ();
      Ok (Some (two, unit C.ANY, `Link))

    | Group (_, (Logop (_, `Or, one, _two))::[]) ->
      emitWarning
        ~value
        "Arbitrarily choosing the first of two options: %s and %s"
        ();
      parse ~emitWarning one

    | Option (_, String (_, name), option::[]) ->
      let deps =
        let open Option.Syntax in
        let%bind spec = parseRange option in
        Some (name, spec, `Link)
      in
      Ok deps

    | _ ->
      let problem = Problem.make ~value "Can't parse this opam dep %s" in
      Error problem
end

let processDeps ~emitWarning deps =
  let open OpamParserTypes in
  let open Result.Syntax in
  let%bind deps =
    match deps with
    | None -> return []
    | Some (List (_, items)) -> return items
    | Some (Group (_, items)) -> return items
    | Some (String (pos, value)) -> return [String (pos, value)]
    | Some value ->
      let problem = Problem.make ~value "unknown value" in
      error problem
  in
  let f (deps, buildDeps, devDeps) dep =
    match ParseDeps.parse ~emitWarning dep with
    | Ok (Some (name, formula, `Link)) ->
      let name = PackageName.(name |> ofString |> toNpm) in
      let spec = Package.VersionSpec.Opam formula in
      let req = Package.Req.ofSpec ~name ~spec in
      return (req::deps, buildDeps, devDeps)
    | Ok (Some (name, formula, `Build)) ->
      let name = PackageName.(name |> ofString |> toNpm) in
      let spec = Package.VersionSpec.Opam formula in
      let req = Package.Req.ofSpec ~name ~spec in
      return (deps, req::buildDeps, devDeps)
    | Ok (Some (name, formula, `Test)) ->
      let name = PackageName.(name |> ofString |> toNpm) in
      let spec = Package.VersionSpec.Opam formula in
      let req = Package.Req.ofSpec ~name ~spec in
      return (deps, buildDeps, req::devDeps)
    | Ok None ->
      return (deps, buildDeps, devDeps)
    | Error msg -> error msg
  in
  Result.List.foldLeft ~f ~init:([], [], []) deps

let processCommandList ~emitWarning item =
  let open Result.Syntax in
  let open OpamParserTypes in
  let processCommand items =
    let f item =
      match item with
      | String (_, value) -> Some value
      | Ident (_, ident) -> Some ("%{" ^ ident ^ "}%")
      | Option (_, _, Ident (_, "preinstalled")::[]) -> None
      | Option (_, _, String (_, _something)::[]) -> None
      | Option (_, String (_, name), Pfxop (_, `Not, (Ident (_, ("preinstalled"))))::[]) -> Some name
      | value ->
        emitWarning ~value "invalid command item" ();
        None
    in
    items
    |> List.map ~f
    |> List.filterNone
  in
  match item with
  | None -> return []
  | Some (List (_, items))
  | Some (Group (_, items)) -> begin
    match items with
      | (String _ | Ident _)::_rest -> return [processCommand items]
      | items ->
        let f item =
          match item with
          | List (_, items) -> Some (processCommand items)
          | Option (_, List (_, items), _) -> Some (processCommand items)
          | value ->
            emitWarning ~value "skipping a non-list build thing" ();
            None
        in
        return (
          items
          |> List.map ~f
          |> List.filterNone
        )
    end
  | Some (Ident (_, ident)) -> return [["%{" ^ ident ^ "}%"]]

  | Some value ->
    let problem = Problem.make ~value "unexpected command" in
    error problem

let parsePatches ~emitWarning item =
  let open Result.Syntax in
  let open OpamParserTypes in

  let%bind items =
    match item with
    | None -> return []
    | Some (List (_, items))
    | Some (Group (_, items)) -> return items

    | Some (String _ as item) -> return [item]
    | Some value ->
      let problem =
        Problem.make
          ~value
          "unexpected type for a string list"
      in error problem
  in

  let f value =
    match value with
    | String (_, name) -> Some name
    | Option (_, String (_, name), Relop (_, `Eq, Ident (_, "os"), String (_, "darwin"))::[]) ->
      Some name
    | Option (_, String (_, _name), Relop (_, `Eq, Ident (_, "os"), String (_, _))::[]) -> None
    | Option (_, String (_, _name), Ident (_, "preinstalled")::[]) -> None
    | Option (_, String (_, name), Pfxop (_, `Not, Ident (_, "preinstalled"))::[]) -> Some name
    | value ->
      emitWarning ~value "do not know how to parse as patch" ();
      None
  in
  return (items |> List.map ~f |> List.filterNone)

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

let getSubsts value =
  let open Result.Syntax in
  let open OpamParserTypes in
  let%bind items =
    match value with
    | None -> return []
    | Some (List (_, items)) ->
      let f value =
        match value with
        | String (_, text) -> return text
        | _ -> error (Problem.make ~value "Bad substs item")
      in
      Result.List.map ~f items
    | Some (String (_, text)) -> return [text]
    | Some value -> error (Problem.make ~value "Bad substs item")
  in
  return (List.map ~f:(fun filename -> ["substs"; filename ^ ".in"]) items)

let toPackageJson manifest version =
  let commandListToJson =
    let f items = `List (List.map ~f:(fun item -> `String item) items) in
    List.map ~f
  in
  let npmName = PackageName.toNpm manifest.name in
  let exportedEnv = manifest.exportedEnv in
  let packageJson =
    `Assoc [
      "name", `String npmName;
      "version", `String (Package.Version.toNpmVersion version);
      "esy", `Assoc [
        "build", `List (commandListToJson manifest.build);
        "install", `List (commandListToJson manifest.install);
        "buildsInSource", `Bool true;
        "exportedEnv", Package.ExportedEnv.to_yojson exportedEnv;
      ];
      "peerDependencies", Dependencies.to_yojson manifest.peerDependencies;
      "optDependencies", Dependencies.to_yojson manifest.optDependencies;
      "dependencies", Dependencies.to_yojson manifest.dependencies;
    ]
  in
  {
    Package.OpamInfo.packageJson = packageJson;
    files = (manifest.files);
    patches = (manifest.patches)
  }

let parseManifest ~name ~version { OpamParserTypes. file_contents; file_name } =
  let open Result.Syntax in

  let warnings = ref [] in
  let emitWarning ~value message () =
    let warning = Problem.make ~value message in
    warnings := warning::!warnings
  in

  let%bind (deps, buildDeps, devDeps) =
    processDeps ~emitWarning (findVariable "depends" file_contents)
  in
  let%bind (depopts, _, _) =
    processDeps ~emitWarning (findVariable "depopts" file_contents)
  in
  let files =
    getOpamFiles Path.(v file_name |> parent)
    |> RunAsync.runExn ~err:"error crawling files"
  in
  let%bind patches =
    parsePatches
      ~emitWarning
      (findVariable "patches" file_contents)
  in
  let ocamlRequirement =
    let req = findVariable "available" file_contents in
    let req = Option.map ~f:OpamAvailable.getOCamlVersion req in
    Option.orDefault ~default:SemverVersion.Formula.any req
  in
  let ourMinimumOcamlVersion = SemverVersion.Version.parseExn "4.2.3" in
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
      Package.Req.ofSpec
        ~name:"ocaml"
        ~spec:(
          Npm SemverVersion.Formula.(DNF.conj
            ocamlRequirement
            (OR [AND [Constraint.GTE ourMinimumOcamlVersion]]))
          )
    in
    let substDep =
      Package.Req.ofSpec
        ~name:"@esy-ocaml/substs"
        ~spec:(Npm SemverVersion.Formula.any)
    in
    let esyInstallerDep =
      Package.Req.ofSpec
        ~name:"@esy-ocaml/esy-installer"
        ~spec:(Npm SemverVersion.Formula.any)
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

  let%bind build =
    let%bind preCmds = getSubsts (findVariable "substs" file_contents) in
    let%bind cmds = processCommandList ~emitWarning (findVariable "build" file_contents) in
    return (preCmds @ cmds)
  in

  let%bind install =
    let installCmds = [["sh"; "-c"; "(esy-installer || true)";]] in
    let%bind cmds = processCommandList ~emitWarning (findVariable "install" file_contents) in
    return (cmds @ installCmds)
  in

  let manifests = {
    name;
    version;
    fileName = file_name;
    build;
    install;
    patches;
    files;
    dependencies;
    devDependencies;
    optDependencies;
    buildDependencies = Dependencies.empty;
    peerDependencies = Dependencies.empty;
    available = isAvailable;
    source = Package.Source.NoSource;
    exportedEnv = []
  } in

  return (manifests, !warnings)

let parseUrl { OpamParserTypes. file_contents; file_name } =
  let open Result.Syntax in
  match findArchive file_contents file_name with
  | None -> begin
    match findVariable "git" file_contents with
    | Some (String (_, remote)) -> return (Package.SourceSpec.Git {remote; ref = None}, [])
    | _ ->
      let problem = Problem.make "no archive found" in
      error problem
    end
  | Some archive ->
      let checksum =
        match findVariable "checksum" file_contents with
        | Some (String (_, checksum)) -> Some checksum
        | _ -> None
      in
      return (Package.SourceSpec.Archive (archive, checksum), [])

let runParsePath ~parser path =
  let open RunAsync.Syntax in

  let logProblem lvl p =
    Logs_lwt.msg lvl (fun m ->
      m "@[<v>Problem found while parsing opam@\n%a@\n%a@]"
      Path.pp path Problem.pp p)
  in

  let%bind data = Fs.readFile path in
  let value = OpamParser.string data (Path.toString path) in
  match parser value with
  | Ok (value, []) -> return value
  | Ok (value, warnings) ->
    Lwt_list.iter_s (logProblem Logs.Warning) warnings;%lwt
    return value
  | Error p ->
    logProblem Logs.Error p;%lwt
    error "error reading opam file"

let toPackage ?name ?version (manifest : t) =
  let open Run.Syntax in
  let name =
    match name with
    | Some name -> name
    | None -> PackageName.toNpm manifest.name
  in
  let version =
    match version with
    | Some version -> version
    | None -> Package.Version.Opam manifest.version
  in
  let source =
    match version with
    | Package.Version.Source src -> src
    | _ -> manifest.source
  in
  return {
    Package.
    name;
    version;
    dependencies = manifest.dependencies;
    devDependencies = manifest.devDependencies;
    source;
    opam = Some (toPackageJson manifest version);
    kind = Esy;
  }
