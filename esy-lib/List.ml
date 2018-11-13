include ListLabels

let filterNone xs =
  let rec loop o accum =
    match o with
    | [] -> accum
    | (Some v)::tl -> loop tl (v :: accum)
    | None::tl -> loop tl accum
  in
  rev (loop xs [])

let rec filter_map ~f = function
    [] -> []
  | a::l -> match f a with 
            | Some r -> r :: filter_map ~f l
            | None   -> filter_map ~f l


let diff xs ys =
  filter ~f:(fun elem -> not (mem ~set:ys elem)) xs

let intersect xs ys =
  filter ~f:(fun elem -> mem ~set:ys elem) xs
