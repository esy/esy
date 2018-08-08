## Global variables

- opam-version: the version of the running opam
- root: the current opam root (e.g. ~/.opam)
- jobs: opam's jobs (-j) parameter, i.e. the number of parallel builds opam is
  allowed to run
- make: the system's make command to use
- arch: the host architecture, typically one of "x86_32", "x86_64", "ppc32",
  "ppc64", "arm32" or "arm64", or the lowercased output of uname -m, or
  "unknown"
- os: the running OS, typically one of "linux", "macos", "win32", "cygwin",
  "freebsd", "openbsd", "netbsd" or "dragonfly", or the lowercased output of
  uname -s, or "unknown"
- os-distribution: the distribution of the OS, one of "homebrew", "macports" on
  "macos", or "android" or the Linux distribution name on Linux. Equal to the
  value of os in other cases or if it can't be detected
- os-family: the more general distribution family, e.g. "debian" on Ubuntu,
  "windows" on Win32 or Cygwin, "bsd" on all bsds. Useful e.g. to detect the
  main package manager
- os-version: the release id of the distribution when applicable, or system
  otherwise
