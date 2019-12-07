/**
 * Output trees on terminal
*/;

type t =
  | Node({
      line: string,
      children: list(t),
    });

let render = (node: t) => {
  let rec nodeToLines = (~indent, ~lines, Node({line, children})) => {
    let lines = {
      let indent = indent |> List.rev |> StringLabels.concat(~sep="");
      [indent ++ line, ...lines];
    };

    let indent =
      switch (indent) {
      | [] => []
      | ["└── ", ...indent] => ["    ", ...indent]
      | [_, ...indent] => ["│   ", ...indent]
      };

    nodeListToLines(~indent, ~lines, children);
  }
  and nodeListToLines = (~indent, ~lines) =>
    fun
    | [] => lines
    | [node] => nodeToLines(~indent=["└── ", ...indent], ~lines, node)
    | [node, ...nodes] => {
        let lines =
          nodeToLines(~indent=["├── ", ...indent], ~lines, node);
        nodeListToLines(~indent, ~lines, nodes);
      };

  node
  |> nodeToLines(~indent=[], ~lines=[])
  |> List.rev
  |> StringLabels.concat(~sep="\n");
};
