module Let_syntax = Run.Let_syntax

module F = OpamFile.Dot_install

(* This checks if we should try adding .exe extension *)
let shouldTryAddExeIfNotExist =
  match Sys.getenv_opt "ESY_INSTALLER__FORCE_EXE", EsyLib.System.Platform.host with
    | (None | Some "false"), Windows -> true
    | (None | Some "false"), (Linux | Darwin | Unix | Cygwin) -> false
    | (None | Some "false"), Unknown -> true  (* won't make it worse, I guess *)
    | Some _, _ -> true

let setExecutable perm = perm lor 0o111
let unsetExecutable perm = perm land (lnot 0o111)

let installFile
  ?(executable=false)
  ~enableLinkingOptimization
  ~rootPath
  ~prefixPath
  ~(dstFilename : Fpath.t option)
  (src : OpamTypes.basename OpamTypes.optional)
  =
  let srcPath =
    let path = src.c |> OpamFilename.Base.to_string |> Fpath.v in
    if Fpath.is_abs path
    then path
    else Fpath.(rootPath // path)
  in
  let dstPath =
    match dstFilename with
    | None -> Fpath.(prefixPath / Fpath.basename srcPath)
    | Some dstFilename -> Fpath.(prefixPath // dstFilename)
  in

  let rec copy ~tryAddExeIfNotExist srcPath dstPath =
    match Run.statIfExists srcPath with
    | Ok None ->
      if tryAddExeIfNotExist && not (Fpath.has_ext ".exe" srcPath)
      then
        let srcPath = Fpath.add_ext ".exe" srcPath in
        let dstPath = Fpath.add_ext ".exe" dstPath in
        copy ~tryAddExeIfNotExist:false srcPath dstPath
      else
        if src.optional
        then Run.return ()
        else Run.errorf "source path %a does not exist" Fpath.pp srcPath

    | Ok Some stats ->
      let origPerm = stats.Unix.st_perm in
      let perm =
        if executable
        then setExecutable origPerm
        else unsetExecutable origPerm
      in
      let%bind () = Run.mkdir (Fpath.parent dstPath) in
      let%bind () =
        if enableLinkingOptimization && origPerm = perm
        then
          match EsyLib.System.Platform.host with
          | Windows -> Run.link ~force:true ~target:srcPath dstPath
          | _ -> Run.symlink ~force:true ~target:srcPath dstPath
        else
          Run.copyFile ~perm srcPath dstPath
      in
      Run.return ()

    | Error error ->
      if src.optional
      then Run.return ()
      else Error error
  in

  copy ~tryAddExeIfNotExist:shouldTryAddExeIfNotExist srcPath dstPath

  let installSection ~enableLinkingOptimization ~executable ?makeDstFilename ~rootPath ~prefixPath files =
    let rec aux = function
      | [] -> Run.return ()
      | (src, dstFilenameSpec)::rest ->
        let dstFilename =
          match dstFilenameSpec, makeDstFilename with
          | Some name, _ -> Some (Fpath.v (OpamFilename.Base.to_string name))
          | None, Some makeDstFilename ->
            let src = Fpath.v (OpamFilename.Base.to_string src.OpamTypes.c) in
            Some (makeDstFilename src)
          | None, None -> None
        in
        let%bind () = installFile ~executable ~enableLinkingOptimization ~rootPath ~prefixPath ~dstFilename src in
        aux rest
    in
    aux files

let install ~enableLinkingOptimization ~prefixPath filename =

  let rootPath = Fpath.parent filename in

  let%bind packageName, spec =
    let%bind data = Run.read filename in
    let packageName = Fpath.basename (Fpath.rem_ext filename) in
    let spec =
      let filename = OpamFile.make (OpamFilename.of_string (Fpath.to_string filename)) in
      F.read_from_string ~filename data
    in
    Run.return (packageName, spec)
  in

  (* See
    *
    *   https://opam.ocaml.org/doc/2.0/Manual.html#lt-pkgname-gt-install
    *
    * for explanations on each section.
    *)

  let%bind () =
    installSection
      ~enableLinkingOptimization
      ~executable:false
      ~rootPath
      ~prefixPath:Fpath.(prefixPath / "lib" / packageName)
      (F.lib spec)
  in

  let%bind () =
    installSection
      ~enableLinkingOptimization
      ~executable:false
      ~rootPath
      ~prefixPath:Fpath.(prefixPath / "lib")
      (F.lib_root spec)
  in

  let%bind () =
    installSection
      ~enableLinkingOptimization
      ~executable:true
      ~rootPath
      ~prefixPath:Fpath.(prefixPath / "lib" / packageName)
      (F.libexec spec)
  in

  let%bind () =
    installSection
      ~enableLinkingOptimization
      ~executable:true
      ~rootPath
      ~prefixPath:Fpath.(prefixPath / "lib")
      (F.libexec_root spec)
  in

  let%bind () =
    installSection
      ~enableLinkingOptimization
      ~executable:true
      ~rootPath
      ~prefixPath:Fpath.(prefixPath / "bin")
      (F.bin spec)
  in

  let%bind () =
    installSection
      ~enableLinkingOptimization
      ~executable:true
      ~rootPath
      ~prefixPath:Fpath.(prefixPath / "sbin")
      (F.sbin spec)
  in

  let%bind () =
    installSection
      ~enableLinkingOptimization
      ~executable:false
      ~rootPath
      ~prefixPath:Fpath.(prefixPath / "lib" / "toplevel")
      (F.toplevel spec)
  in

  let%bind () =
    installSection
      ~enableLinkingOptimization
      ~executable:false
      ~rootPath
      ~prefixPath:Fpath.(prefixPath / "share" / packageName)
      (F.share spec)
  in

  let%bind () =
    installSection
      ~enableLinkingOptimization
      ~executable:false
      ~rootPath
      ~prefixPath:Fpath.(prefixPath / "share")
      (F.share_root spec)
  in

  let%bind () =
    installSection
      ~enableLinkingOptimization
      ~executable:false
      ~rootPath
      ~prefixPath:Fpath.(prefixPath / "etc" / packageName)
      (F.etc spec)
  in

  let%bind () =
    installSection
      ~enableLinkingOptimization
      ~executable:false
      ~rootPath
      ~prefixPath:Fpath.(prefixPath / "doc" / packageName)
      (F.doc spec)
  in

  let%bind () =
    installSection
      ~enableLinkingOptimization
      ~executable:true
      ~rootPath
      ~prefixPath:Fpath.(prefixPath / "lib" / "stublibs")
      (F.stublibs spec)
  in

  let%bind () =
    let makeDstFilename src =
      let num = Fpath.get_ext src in
      Fpath.(v ("man" ^ num) / basename src)
    in
    installSection
      ~enableLinkingOptimization
      ~executable:false
      ~makeDstFilename
      ~rootPath
      ~prefixPath:Fpath.(prefixPath / "man")
      (F.man spec)
  in

  Run.return ()
