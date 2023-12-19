---
id: npm-like-solver-for-opam
title: NPM like solver for OPAM
---

# Table of Contents

1.  [Abstract](#org337017e)
2.  [Definitions](#org862d3f5)
    1.  [Package Local Resolution of Dependency modules](#org122de3e)
3.  [Design goals](#org5758dd1)
4.  [Scope](#org2d33519)
    1.  [What it does?](#orga7583a7)
    2.  [What it doesn't?](#org9667071)
5.  [Implementation details](#org693ed68)
	1.  [document esy's override mechanism](#org0e49b21)
	2.  [Why override mechanism?](#org11c6d58)
6.  [What will the rules look like?](#org9285925)
	1.  [Implementation for non-dune projects](#orgb46bfb8)


<a id="org337017e"></a>

# Abstract

OCaml sandboxes do not allow more than one version of a package to be
linked in. This is because of absence of package local resolution of
dependency modules. This document describes a namespacing approach
that could enable such linking of dependencies local to a package so
that a higher level package sandbox doesn't see conflicts.


<a id="org862d3f5"></a>

# Definitions


<a id="org122de3e"></a>

## Package Local Resolution of Dependency modules

Languages runtimes like Node.js have in-built namespacing - a variable
(symbol) declared in one `.js` file isn't visible unless exported.

    const lodash = require("lodash"); // v1

This declaration is hidden from all other modules (as a part of it's
closure/environment). Which is why another module/package importing
`lodash` of a different version doesn't conflict.

This isn't possible by default in the natively compiled world -
linkers, on seeing a symbol (say lodash), would assume the same
interface (more correctly memory layout) everywhere as there is no
concept of private variables in ASM/CPU instructions.

We define, in this document, the ability to load a dependency module
and keep it visible only locally as "Package local resolution of
dependency modules"

For good explanation, see this [article from MDN](https://hacks.mozilla.org/2015/08/es6-in-depth-modules/)
Particularly note,

> Linking: For each newly loaded module, the implementation creates a
> module scope and fills it with all the bindings declared in that
> module, including things imported from other modules. 

<a id="org5758dd1"></a>

# Design goals

Allow more than one versions of an opam or native C package in the
same sandbox while,

1.  Adding no extra step for user
2.  No break existing tools like LSP


<a id="org2d33519"></a>

# Scope


<a id="orga7583a7"></a>

## What it does?

Allow more than one versions of an opam or native C package in the
same sandbox with namespacing package libraries


<a id="org9667071"></a>

## What it doesn't?

1.  Write a new solver
2.  Patch existing solver


<a id="org693ed68"></a>

# Implementation details

With [pesy](https://github.com/esy/pesy), we experimented with named imports.

    "imports": [
      "Yojson2 = require('@opam/yojson')"
    ],

We were able to rename exported namespace, `Yojson`, to anything
arbitrary (here, `Yojson2`)

We did this by adding the following dune rules on the fly,

    (executables
     (names FooApp)
     (modules (:standard \ FooBinPesyModules))
     (public_names FooApp) (libraries foo.bin.pesy-modules)
     (flags -open FooBinPesyModules))
    
    (library
     (public_name foo.bin.pesy-modules)
     (name FooBinPesyModules)
     (modules FooBinPesyModules)
     (libraries foo.library))
    
    (rule
     (with-stdout-to FooBinPesyModules.re
      (run echo "module Yojson2 = Yojson;")))

We can, similarly, append such Dune rules on-the-fly via esy's
overrides mechanism

\#+BEGIN<sub>COMMENT</sub>


<a id="org0e49b21"></a>

### TODO document esy's override mechanism

\#+END<sub>COMMENT</sub>


<a id="org11c6d58"></a>

### Why override mechanism?

Original sources wont be mutated and can be re-used if user wishes to
opt-out of this feature altogether.


<a id="org9285925"></a>

## What will the rules look like?

Let's take `Yojson` as an example. The dune file looks like this

    (library
     (name yojson)
     (public_name yojson)
     (modules yojson t basic safe raw common codec lexer_utils)
     (synopsis "JSON parsing and printing")
     (libraries seq)
     (flags
      (:standard -w -27-32)))

[Reference](https://github.com/ocaml-community/yojson/blob/4c1d4b52f9e87a4bd3b7f26111e8a4976c1e8676/lib/dune#L111-L118)

1.  For version `2.1.2`, we could patch it to,

```
    (library
     (name yojson_v2_1_2)
     (public_name yojson_v2_1_2)
     (modules yojson_v2_1_2 t basic safe raw common codec lexer_utils)
     (synopsis "JSON parsing and printing")
     (libraries seq)
     (flags
      (:standard -w -27-32)))
```

1.  Rename the entrypoint from `yojson.ml` to `yojson_v2_1_2.ml`

2.  Add the following rule aliasing `Yojson_v2_1_2` to `Yojson`

```
    (rule
     (with-stdout-to Yojson_alias.re
         (run echo "module Yojson = Yojson_v2_1_2;")))
```

1.  Create an alias library

```
    (library
     (name Yojson_alias)
     (modules Yojson_alias)
     (libraries yojson_v2_1_2))
```

1.  Use this in the consuming package

```
    (executables
     (names FooApp)
     (modules (:standard \ Yojson_alias))
     (public_names FooApp)
     (libraries Yojson_alias)
     (flags -open Yojson_alias))
```


<a id="orgb46bfb8"></a>

### Implementation for non-dune projects

TODO

