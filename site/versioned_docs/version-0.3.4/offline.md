---
id: version-0.3.4-offline
title: Offline Builds
original_id: offline
---

esy supports workflow there builds should happen on a machine which is
completely offline (doesn't have network access).

To do that you need to use `--cache-tarballs-path` option of `esy install`
command:

1.  On a machine which has network access execute:

    ```bash
    % esy install --cache-tarballs-path=./_esyinstall
    ```

    this will create `_esyinstall` directory with all downloaded dependencies'
    sources.

2.  Tranfer an entire project directory along with `_esyinstall` (but withiout
    `node_modules` as it could contain platform specific artifacts) to a machine
    which doesn't have access to an external network.

3.  Execute the same installation command

    ```bash
    % esy install --cache-tarballs-path=./_esyinstall
    ```

    which will populate `node_modules` directory with extracted sources.

4.  Run

    ```bash
    % esy build
    ```

    and other esy commands.
