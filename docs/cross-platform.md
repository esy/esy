# Cross-Platform Development with `esy`

## Goal

The goal for `esy` is to work equally well on Linux, Windows, and OSX - without needing special cases or hacks.

The development workflow for `esy` should be the same for all of these platforms.

## Architecture

One challenge with the OCaml ecosystem is that many of the scripts rely heavily on 'bashisms', like `make`, bash shell scripts, etc.

Unfortunately, those tools aren't available out-of-the-box on Windows. WSL is starting to offer more capabilities around this,
but there isn't a seamless install story. An important piece of meeting our goal stated above is that the installation process
for `esy` is simple - `npm install -g esy`.

To that end, we use `cygwin` on Windows to provide a transparent layer for running these 'bashisms'. You don't even have to know about it -
we install it silently, keep it in a sandbox, and delegate commands to it under the hood- but you don't need to touch it for `esy`. As we
improve native package support, we might not even need this layer long-term, but it helps get us started with a seamless windows experience.

### Path considerations

A major difference with Windows vs OSX/Linux is the path separator - `\` vs `/`. Windows can actually work with _either_ path separator (for the most part). 

The challenge, though, is `\` is also the __escape character__ - so we can hit double-escaping issues when we render the strings.

For the time being, we'll __normalize all paths to use a forward slash__ - this keeps us from hitting the 'double-escaping issues' with backslash.

One other complexity is that we use Cygwin for running our build tasks, and the canonical paths for Cygwin are POSIX style, like:
- `C:\temp` -> ``/cygdrive/c/temp`

However, the majority of Cygwin utilities can work with either style of paths - therefore, we will use the the Windows path, normalized with a forward slash, for shell invocations.

For utilities that do not support this - like `rsync` - we will convert the path to a cygwin-style path. Cygwin includes the `cygpath` utility for this.

### Cross-platform environment variables

Another difference in Windows vs OSX/Linux is how the environment variables separate individual paths. On POSIX systems, it's a colon - `:` - on Windows, its `;`

Because our __built artifacts are native__, we must use native Windows paths in our environment variables (normalized with forward slash).

### Other considerations

- Windows has a `PATH` limit of `260`. Newer APIs no longer have this limit, but they are opt-in. You can also set a registry key to fix this, but again, it's opt-in. Something to be mindful of if your tool creates lots of nested paths!
