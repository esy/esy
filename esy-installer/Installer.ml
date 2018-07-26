module type IO = sig

  type 'v computation
  val return : 'v -> 'v computation
  val error : string -> 'v computation
  val bind : f:('v1 -> 'v2 computation) -> 'v1 computation -> 'v2 computation
  val handle : 'v computation -> ('v, string) result computation

  module Fs : sig
    val mkdir : Fpath.t -> unit computation
    val readdir : Fpath.t -> Fpath.t list computation
    val read : Fpath.t -> string computation
    val write : ?perm:int -> data:string -> Fpath.t -> unit computation
    val stat : Fpath.t -> Unix.stats computation
  end
end

module type INSTALLER = sig
  type 'v computation
  val run : rootPath:Fpath.t -> prefixPath:Fpath.t -> string option -> unit computation
end

module Make (Io : IO) : INSTALLER with type 'v computation = 'v Io.computation = struct

  open Io

  type nonrec 'v computation = 'v computation

  module Let_syntax = struct
    let bind = bind
  end

  module F = OpamFile.Dot_install

  let setExecutable perm = perm lor 0o111
  let unsetExecutable perm = perm land (lnot 0o111)

  let installFile
    ?(executable=false)
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
    match%bind handle (Fs.stat srcPath) with
    | Ok stats ->
      let perm =
        if executable
        then setExecutable stats.Unix.st_perm
        else unsetExecutable stats.Unix.st_perm
      in
      let%bind () = Fs.mkdir (Fpath.parent dstPath) in
      let%bind () =
        let%bind data = Fs.read srcPath in
        Fs.write ~data ~perm dstPath
      in
      return ()
    | Error msg ->
      if src.optional
      then return ()
      else error msg

    let installSection ?executable ?dstFilename ~rootPath ~prefixPath files =
      let rec aux = function
        | [] -> return ()
        | (src, dstFilenameSpec)::rest ->
          let dstFilename =
            match dstFilenameSpec, dstFilename with
            | Some name, _ -> Some (Fpath.v (OpamFilename.Base.to_string name))
            | None, Some dstFilename ->
              let src = Fpath.v (OpamFilename.Base.to_string src.OpamTypes.c) in
              Some (dstFilename src)
            | None, None -> None
          in
          let%bind () = installFile ?executable ~rootPath ~prefixPath ~dstFilename src in
          aux rest
      in
      aux files

  let run ~(rootPath : Fpath.t) ~(prefixPath : Fpath.t) (filename : string option) =

    let%bind (packageName, spec) =
      let%bind filename =
        match filename with
        | Some name -> return Fpath.(rootPath / name)
        | None ->
          let%bind items = Fs.readdir rootPath in
          let isInstallFile filename = Fpath.has_ext ".install" filename in
          begin match List.filter isInstallFile items with
          | [filename] -> return filename
          | [] -> error "no *.install files found"
          | _ -> error "multiple *.install files found"
          end
        in
      let%bind data = Fs.read filename in
      let packageName = Fpath.basename (Fpath.rem_ext filename) in
      let spec =
        let filename = OpamFile.make (OpamFilename.of_string (Fpath.to_string filename)) in
        F.read_from_string ~filename data
      in
      return (packageName, spec)
    in

    (* See
     *
     *   https://opam.ocaml.org/doc/2.0/Manual.html#lt-pkgname-gt-install
     *
     * for explanations on each section.
     *)

    let%bind () =
      installSection
        ~rootPath
        ~prefixPath:Fpath.(prefixPath / "lib" / packageName)
        (F.lib spec)
    in

    let%bind () =
      installSection
        ~rootPath
        ~prefixPath:Fpath.(prefixPath / "lib")
        (F.lib_root spec)
    in

    let%bind () =
      installSection
        ~executable:true
        ~rootPath
        ~prefixPath:Fpath.(prefixPath / "lib" / packageName)
        (F.libexec spec)
    in

    let%bind () =
      installSection
        ~executable:true
        ~rootPath
        ~prefixPath:Fpath.(prefixPath / "lib")
        (F.libexec_root spec)
    in

    let%bind () =
      installSection
        ~executable:true
        ~rootPath
        ~prefixPath:Fpath.(prefixPath / "bin")
        (F.bin spec)
    in

    let%bind () =
      installSection
        ~executable:true
        ~rootPath
        ~prefixPath:Fpath.(prefixPath / "sbin")
        (F.sbin spec)
    in

    let%bind () =
      installSection
        ~rootPath
        ~prefixPath:Fpath.(prefixPath / "lib" / "toplevel")
        (F.toplevel spec)
    in

    let%bind () =
      installSection
        ~rootPath
        ~prefixPath:Fpath.(prefixPath / "share" / packageName)
        (F.share spec)
    in

    let%bind () =
      installSection
        ~rootPath
        ~prefixPath:Fpath.(prefixPath / "share")
        (F.share_root spec)
    in

    let%bind () =
      installSection
        ~rootPath
        ~prefixPath:Fpath.(prefixPath / "etc" / packageName)
        (F.etc spec)
    in

    let%bind () =
      installSection
        ~rootPath
        ~prefixPath:Fpath.(prefixPath / "doc" / packageName)
        (F.doc spec)
    in

    let%bind () =
      installSection
        ~executable:true
        ~rootPath
        ~prefixPath:Fpath.(prefixPath / "lib" / "stublibs")
        (F.stublibs spec)
    in

    let%bind () =
      let dstFilename src =
        let num = Fpath.get_ext src in
        Fpath.(v ("man" ^ num) / basename src)
      in
      installSection
        ~dstFilename
        ~rootPath
        ~prefixPath:Fpath.(prefixPath / "man")
        (F.man spec)
    in

    return ()

end
