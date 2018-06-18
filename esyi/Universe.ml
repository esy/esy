module Version = PackageInfo.Version
module VersionSpec = PackageInfo.VersionSpec
module Req = PackageInfo.Req

module CudfName = struct

  let escapeWith = "UuU"
  let underscoreRe = Re.(compile (char '_'))
  let underscoreEscapeRe = Re.(compile (str escapeWith))

  let ofString name =
    Re.replace_string underscoreRe ~by:escapeWith name

  let toString name =
    Re.replace_string underscoreEscapeRe ~by:"_" name
end

type t = Package.t Version.Map.t StringMap.t
type univ = t

let empty = StringMap.empty

let add ~pkg (univ : t) =
  let {Package. name; version; _} = pkg in
  let versions =
    match StringMap.find_opt name univ with
    | None -> Version.Map.empty
    | Some versions -> versions
  in
  StringMap.add name (Version.Map.add version pkg versions) univ

let mem ~pkg univ =
  match StringMap.find pkg.Package.name univ with
  | None -> false
  | Some versions -> Version.Map.mem pkg.Package.version versions

let findVersion ~name ~version (univ : t) =
  match StringMap.find name univ with
  | None -> None
  | Some versions -> Version.Map.find_opt version versions

let findVersionExn ~name ~version (univ : t) =
  match findVersion ~name ~version univ with
  | Some pkg -> pkg
  | None ->
    let msg =
      Printf.sprintf
        "inconsistent state: package not in the universr %s@%s"
        name (PackageInfo.Version.toString version)
    in
    failwith msg

let findVersions ~name univ =
  match StringMap.find name univ with
  | None -> []
  | Some versions ->
    versions
    |> Version.Map.bindings
    |> List.map ~f:(fun (_, pkg) -> pkg)

module CudfVersionMap = struct

  module VersionSet = Set.Make(Package.Version)

  type t = {
    cudfVersionToVersion: ((string * int), PackageInfo.Version.t) Hashtbl.t ;
    versionToCudfVersion: ((string * PackageInfo.Version.t), int) Hashtbl.t;
    versions : (string, VersionSet.t) Hashtbl.t;
  }

  let make ?(size=100) () = {
    cudfVersionToVersion = Hashtbl.create size;
    versionToCudfVersion = Hashtbl.create size;
    versions = Hashtbl.create size;
  }

  let update map name version cudfVersion =
    Hashtbl.replace map.versionToCudfVersion (name, version) cudfVersion;
    Hashtbl.replace map.cudfVersionToVersion (name, cudfVersion) version;
    let () =
      let versions =
        try Hashtbl.find map.versions name
        with _ -> VersionSet.empty
      in
      let versions = VersionSet.add version versions in
      Hashtbl.replace map.versions name versions
    in
    ()

  let findVersion ~name ~cudfVersion map =
    match Hashtbl.find map.cudfVersionToVersion (name, cudfVersion) with
    | exception Not_found -> None
    | version -> Some version

  let findCudfVersion ~name ~version map =
    match Hashtbl.find map.versionToCudfVersion (name, version) with
    | exception Not_found -> None
    | version -> Some version

  let findVersionExn ~name ~cudfVersion map =
    match findVersion ~name ~cudfVersion map with
    | Some v -> v
    | None ->
      let msg =
        Printf.sprintf
          "inconsistent state: found a package not in the cudf version map %s@cudf:%i\n"
          name cudfVersion
      in
      failwith msg

  let findCudfVersionExn ~name ~version map =
    match findCudfVersion ~name ~version map with
    | Some v -> v
    | None ->
      let msg =
        Printf.sprintf
          "inconsistent state: found a package not in the cudf version map %s@%s"
          name (PackageInfo.Version.toString version)
      in
      failwith msg

end

module CudfMapping = struct

  type t = univ * Cudf.universe * CudfVersionMap.t

  let decodePkg (cudf : Cudf.package) (univ, _cudfUniv, vmap) =
    let name = CudfName.toString cudf.package in
    match CudfVersionMap.findVersion ~name ~cudfVersion:cudf.version vmap with
    | Some version -> findVersion ~name ~version univ
    | None -> None

  let decodePkgExn (cudf : Cudf.package) (univ, _cudfUniv, vmap) =
    let name = CudfName.toString cudf.package in
    let version = CudfVersionMap.findVersionExn ~name ~cudfVersion:cudf.version vmap in
    findVersionExn ~name ~version univ

  let encodePkg (pkg : Package.t) (_univ, cudfUniv, vmap) =
    let name = CudfName.ofString pkg.name in
    match CudfVersionMap.findCudfVersion ~name ~version:pkg.version vmap with
    | Some cudfVersion ->
      begin
        try Some (Cudf.lookup_package cudfUniv (name, cudfVersion))
        with | Not_found -> None
      end
    | None -> None

  let encodePkgExn (pkg : Package.t) (_univ, cudfUniv, vmap) =
    let name = CudfName.ofString pkg.name in
    let cudfVersion = CudfVersionMap.findCudfVersionExn ~name ~version:pkg.version vmap in
    Cudf.lookup_package cudfUniv (name, cudfVersion)

  let univ (univ, _, _) = univ
  let cudfUniv (_, cudfUniv, _) = cudfUniv

end

let toCudf univ =
  let cudfUniv = Cudf.empty_universe () in
  let cudfVersionMap = CudfVersionMap.make () in

  (* We add packages in batch by name so this "set of package names" is
    * enough to check if we have handled a pkg already.
    *)
  let seen, markAsSeen =
    let names = ref StringSet.empty in
    let seen name = StringSet.mem name !names in
    let markAsSeen name = names := StringSet.add name !names in
    seen, markAsSeen
  in

  let updateVersionMap pkgs =
    let f cudfVersion (pkg : Package.t) =
      CudfVersionMap.update
        cudfVersionMap
        pkg.name
        pkg.version
        (cudfVersion + 1);
    in
    List.iteri ~f pkgs;
  in

  let rec encodePkg (pkg : Package.t) =
    let cudfVersion =
      CudfVersionMap.findCudfVersionExn
        ~name:pkg.name
        ~version:pkg.version
        cudfVersionMap
    in

    let depends = List.map ~f:(encodeReq ~from:pkg) pkg.dependencies.dependencies in
    let cudfName = CudfName.ofString pkg.name in
    let cudfPkg = {
      Cudf.default_package with
      package = cudfName;
      version = cudfVersion;
      conflicts = [cudfName, None];
      installed = false;
      depends;
    }
    in
    Cudf.add_package cudfUniv cudfPkg

  and encodeReq ~from:_ req =
    let name = Req.name req in
    let spec = Req.spec req in

    let versions = findVersions ~name univ in

    if not (seen name) then (
      markAsSeen name;
      updateVersionMap versions;
    );

    let versionsMatched =
      List.filter
        ~f:(fun pkg -> VersionSpec.satisfies ~version:pkg.Package.version spec)
        versions
    in

    match versionsMatched with
    | [] ->
      [name, Some (`Eq, 10000000000)]
    | versionsMatched ->
      let pkgToConstraint pkg =
        let cudfVersion =
          CudfVersionMap.findCudfVersionExn
            ~name:pkg.Package.name
            ~version:pkg.Package.version
            cudfVersionMap
        in
        CudfName.ofString pkg.Package.name, Some (`Eq, cudfVersion)
      in
      List.map ~f:pkgToConstraint versionsMatched
  in

  StringMap.iter (fun name _ ->
    let versions = findVersions ~name univ in
    updateVersionMap versions;
    List.iter ~f:encodePkg versions;
  ) univ;

  cudfUniv, (univ, cudfUniv, cudfVersionMap)
