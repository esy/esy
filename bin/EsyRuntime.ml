let currentWorkingDir = Path.v (Sys.getcwd ())
let currentExecutable = Path.v Sys.executable_name

let resolve req =
  match NodeResolution.resolve req with
  | Ok path -> path
  | Error (`Msg err) -> failwith err

module EsyPackageJson = struct
  type t = {
    version : string
  } [@@deriving of_yojson { strict = false }]

  let read () =
    let pkgJson =
      let open RunAsync.Syntax in
      let filename = resolve "../../../package.json" in
      let%bind data = Fs.readFile filename in
      Lwt.return (Json.parseStringWith of_yojson data)
    in Lwt_main.run pkgJson
end

let version =
  match EsyPackageJson.read () with
  | Ok pkgJson -> pkgJson.EsyPackageJson.version
  | Error err ->
    let msg =
      let err = Run.formatError err in
      Printf.sprintf "invalid esy installation: cannot read package.json %s" err in
    failwith msg

let concurrency =
  (** TODO: handle more platforms, right now this is tested only on macOS and Linux *)
  let cmd = Bos.Cmd.(v "getconf" % "_NPROCESSORS_ONLN") in
  match Bos.OS.Cmd.(run_out cmd |> to_string) with
  | Ok out ->
    begin match out |> String.trim |> int_of_string_opt with
    | Some n -> n
    | None -> 1
    end
  | Error _ -> 1
