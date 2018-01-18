type 'a t = 'a Run.t Lwt.t

let return v = Lwt.return (Ok v)

let error msg =
  Lwt.return (Run.error msg)

let withContext msg v =
  let%lwt v = v in
  Lwt.return (Run.withContext msg v)

let bind ~f v =
  let waitForPromise = function
    | Ok v -> f v
    | Error err -> Lwt.return (Error err)
  in
  Lwt.bind v waitForPromise

let waitAll xs =
  let rec waitAll' xs = match xs with
    | [] -> return ()
    | x::xs ->
      let f () = waitAll' xs in
      bind ~f x
  in
  waitAll' xs

module Syntax = struct
  let return = return
  let error = error

  module Let_syntax = struct
    let bind = bind
  end
end

let liftOfRun = Lwt.return
