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

let both a b =
  let%lwt a = a and b = b in
  Lwt.return (
    match a, b with
    | Ok a, Ok b -> Ok (a, b)
    | Ok _, Error err -> Error err
    | Error err, Ok _ -> Error err
    | Error err, Error _ -> Error err
  )

let ofResult ?err r = 
    match r with
    | Ok v -> return v
    | Error _ ->
            match err with
            | Some e -> error e
            | None -> error "Unknown error"

module Syntax = struct
  let return = return
  let error = error

  module Let_syntax = struct
    let bind = bind
    let both = both
  end
end

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

  let rec processSeq ~f =
    let open Syntax in
    function
    | [] -> return ()
    | x::xs ->
      let%bind () = f x in
      processSeq ~f xs
end
