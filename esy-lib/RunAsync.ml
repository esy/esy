type 'a t = 'a Run.t Lwt.t

let return v = Lwt.return (Ok v)

let error msg =
  Lwt.return (Run.error msg)

let errorf fmt =
  let kerr _ = Lwt.return (Run.error (Format.flush_str_formatter ())) in
  Format.kfprintf kerr Format.str_formatter fmt

let context v msg =
  let%lwt v = v in
  Lwt.return (Run.context v msg)

let contextf v fmt =
  let kerr _ = context v (Format.flush_str_formatter ()) in
  Format.kfprintf kerr Format.str_formatter fmt

let withContextOfLog ?header content v =
  let%lwt v = v in
  Lwt.return (Run.withContextOfLog ?header content v)

let bind ~f v =
  let waitForPromise = function
    | Ok v -> f v
    | Error err -> Lwt.return (Error err)
  in
  Lwt.bind v waitForPromise

let both a b =
  let%lwt a = a and b = b in
  Lwt.return (
    match a, b with
    | Ok a, Ok b -> Ok (a, b)
    | Ok _, Error err -> Error err
    | Error err, Ok _ -> Error err
    | Error err, Error _ -> Error err
  )

let ofRun = Lwt.return
let ofStringError r = ofRun (Run.ofStringError r)
let ofBosError r = ofRun (Run.ofBosError r)

module Syntax = struct
  let return = return
  let error = error
  let errorf = errorf

  module Let_syntax = struct
    let bind = bind
    let both = both
  end
end

let ofOption ?err v =
  match v with
  | Some v -> return v
  | None ->
    let err = match err with
    | Some err -> err
    | None -> "not found"
    in error err

let runExn ?err v =
  let v = Lwt_main.run v in
  Run.runExn ?err v

let cleanup comp handler =
  let res =
    match%lwt comp with
    | Ok res -> return res
    | Error _ as err -> handler () ;%lwt Lwt.return err
  in
  try%lwt res with err -> (handler () ;%lwt raise err)

module List = struct

  let foldLeft ~(f : 'a -> 'b -> 'a t) ~(init : 'a) (xs : 'b list) =
    let rec fold acc xs =
      match%lwt acc with
      | Error err -> Lwt.return (Error err)
      | Ok acc ->
        begin match xs with
        | [] -> return acc
        | x::xs -> fold (f acc x) xs
        end
    in
    fold (return init) xs

  let joinAll xs =
    let rec _joinAll xs res = match xs with
      | [] ->
        return (List.rev res)
      | x::xs ->
        let f v = _joinAll xs (v::res) in
        bind ~f x
    in
    _joinAll xs []

  let waitAll xs =
    let rec _waitAll xs = match xs with
      | [] -> return ()
      | x::xs ->
        let f () = _waitAll xs in
        bind ~f x
    in
    _waitAll xs

  let limitWithConccurrency concurrency f =
    match concurrency with
    | None -> f
    | Some concurrency ->
      let queue = LwtTaskQueue.create ~concurrency () in
      fun x -> LwtTaskQueue.submit queue (fun () -> f x)

  let mapAndWait ?concurrency ~f xs =
    waitAll (List.map ~f:(limitWithConccurrency concurrency f) xs)

  let map ?concurrency ~f xs =
    joinAll (List.map ~f:(limitWithConccurrency concurrency f) xs)

  let filter ?concurrency ~f xs =
    let open Syntax in
    let f x = if%bind f x then return (Some x) else return None in
    let f = limitWithConccurrency concurrency f in
    let%bind xs = joinAll (List.map ~f xs) in
    return (List.filterNone xs)

  let mapAndJoin = map

  let rec processSeq ~f =
    let open Syntax in
    function
    | [] -> return ()
    | x::xs ->
      let%bind () = f x in
      processSeq ~f xs
end
