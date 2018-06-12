include ListLabels

let filterNone xs =
  let rec loop o accum =
    match o with
    | [] -> accum
    | (Some v)::tl -> loop tl (v :: accum)
    | None::tl -> loop tl accum
  in
  rev (loop xs [])

let diff xs ys =
  filter ~f:(fun elem -> not (mem ~set:ys elem)) xs

let intersect xs ys =
  filter ~f:(fun elem -> mem ~set:ys elem) xs
