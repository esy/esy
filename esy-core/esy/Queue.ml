type 'a t = ('a list * 'a list)

let empty =
  ([], [])

let is_empty = function
  | [], [] -> true
  | _, _ -> false

let enqueue el = function
  | [], next -> [el], next
  | cur, next -> cur, el::next

let rec dequeue = function
  | el::cur, next -> (Some el, (cur, next))
  | [], [] -> (None, empty)
  | [], next -> dequeue (List.rev next, [])
