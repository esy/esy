include ListLabels;

let filterNone = xs => {
  let rec loop = (o, accum) =>
    switch (o) {
    | [] => accum
    | [Some(v), ...tl] => loop(tl, [v, ...accum])
    | [None, ...tl] => loop(tl, accum)
    };

  rev(loop(xs, []));
};

let rec filter_map = (~f) =>
  fun
  | [] => []
  | [a, ...l] =>
    switch (f(a)) {
    | Some(r) => [r, ...filter_map(~f, l)]
    | None => filter_map(~f, l)
    };

let diff = (xs, ys) => filter(~f=elem => !mem(~set=ys, elem), xs);

let intersect = (xs, ys) => filter(~f=elem => mem(~set=ys, elem), xs);
