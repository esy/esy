---
id: repl
title: Running REPL
---

`dune utop` doesn't work out of the box with Reason syntax.

There's a script that translates the OCaml syntax into Reason so that `dune utop` can be made to work with `rtop`. It can be run with

```sh
esy ./scripts/top.sh
```
