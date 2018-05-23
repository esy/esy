type 'a t = 'a Run.t Lwt.t

let return v = Lwt.return (Ok v)

let error msg =
  Lwt.return (Run.error msg)

let withContext msg v =
  let%lwt v = v in
  Lwt.return (Run.withContext msg v)

let withContextOfLog ?header content v =
  let%lwt v = v in
  Lwt.return (Run.withContextOfLog ?header content v)

let bind ~f v =
  let waitForPromise = function
    | Ok v -> f v
    | Error err -> Lwt.return (Error err)
  in
  Lwt.bind v waitForPromise

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

module Syntax = struct
  let return = return
  let error = error

  module Let_syntax = struct
    let bind = bind
  end
end

let liftOfRun = Lwt.return
let ofRun = Lwt.return

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
