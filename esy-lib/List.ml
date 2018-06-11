include ListLabels

let filterNone xs =
  let rec loop o accum =
    match o with
    | [] -> accum
    | hd::tl ->
        (match hd with
         | ((Some (v))[@explicit_arity ]) -> loop tl (v :: accum)
         | None -> loop tl accum) in
  loop xs []

let diff xs ys =
  filter ~f:(fun elem -> not (mem ~set:ys elem)) xs

let intersect xs ys =
  filter ~f:(fun elem -> mem ~set:ys elem) xs
