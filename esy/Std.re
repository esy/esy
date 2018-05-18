module List = {
  include List;
  let filterNone = l => {
    let rec loop = (o, accum) =>
      switch (o) {
      | [] => accum
      | [hd, ...tl] =>
        switch (hd) {
        | Some(v) => loop(tl, [v, ...accum])
        | None => loop(tl, accum)
        }
      };
    loop(l, []);
  };
  let diff = (list1, list2) =>
    List.filter(elem => ! List.mem(elem, list2), list1);
  let intersect = (list1, list2) =>
    List.filter(elem => List.mem(elem, list2), list1);
};
