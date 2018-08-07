type t = {
  index : record StringMap.t;
  cacheKey : (string option [@default None]);
} [@@deriving yojson]

and record = {
  url: string;
  md5: string
}

let baseUrl = "https://opam.ocaml.org/"
let url = baseUrl ^ "/urls.txt"

let parse response =

  let parseBase =
    Re.(compile (seq [bos; str "archives/"; group (rep1 any); str "+opam.tar.gz"; eos]))
  in

  let attrs = OpamFile.File_attributes.read_from_string response in
  let f attr index =
    let base = OpamFilename.(Base.to_string (Attribute.base attr)) in
    let md5 =
      let hash = OpamFilename.Attribute.md5 attr in
      OpamHash.contents hash
    in
    match Re.exec_opt parseBase base with
    | Some m ->
      let id = Re.Group.get m 1 in
      let url = baseUrl ^ base in
      let record = {url; md5} in
      StringMap.add id record index
    | None -> index
  in
  OpamFilename.Attribute.Set.fold f attrs StringMap.empty

let download () =
  let open RunAsync.Syntax in
  Logs_lwt.app (fun m -> m "downloading opam index...");%lwt
  let%bind data = Curl.get url in
  return (parse data)

let init ~cfg () =
  let open RunAsync.Syntax in
  let filename = cfg.Config.opamArchivesIndexPath in

  let cacheKeyOfHeaders headers =
    let contentLength = StringMap.find_opt "content-length" headers in
    let lastModified = StringMap.find_opt "last-modified" headers in
    match contentLength, lastModified with
    | Some a, Some b -> Some Digest.(a ^ "__" ^ b |> string |> to_hex)
    | _ -> None
  in

  let save index =
    let json = to_yojson index in
    Fs.writeJsonFile ~json filename
  in

  let downloadAndSave () =
    let%bind headers = Curl.head url in
    let cacheKey = cacheKeyOfHeaders headers in
    let%bind index =
      let%bind index = download () in
      return {cacheKey; index}
    in
    let%bind () = save index in
    return index
  in

  if%bind Fs.exists filename
  then
    let%bind json = Fs.readJsonFile filename in
    let%bind index = RunAsync.ofRun (Json.parseJsonWith of_yojson json) in
    let%bind headers = Curl.head url in
    begin match index.cacheKey, cacheKeyOfHeaders headers with
    | Some cacheKey, Some currCacheKey ->
      if cacheKey = currCacheKey
      then return index
      else
        let%bind index =
          let%bind index = download () in
          return {index; cacheKey = Some currCacheKey}
        in
        let%bind () = save index in
        return index
    | _ -> downloadAndSave ()
    end
  else downloadAndSave ()

let find ~name ~version index =
  let key =
    let name = OpamPackage.Name.to_string name in
    let version = OpamPackage.Version.to_string version in
    name ^ "." ^ version
  in
  StringMap.find_opt key index.index
