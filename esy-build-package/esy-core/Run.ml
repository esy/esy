type ('a, 'b) t = ('a, 'b) result Lwt.t

module Let_syntax = struct

  let bind ~f (v: ('a, 'b) t) =
    match%lwt v with
    | Ok(v) -> f(v)
    | Error(e) -> Lwt.return(Error(e))

end

let return v = Lwt.return(Ok(v))
let error err = Lwt.return(Error(err))
