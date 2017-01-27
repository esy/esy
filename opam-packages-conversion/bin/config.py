import os.path

__dir__ = os.path.dirname(os.path.realpath(__file__))

os.environ['PATH'] = '%s:%s' % (__dir__, os.environ['PATH'])

GH_ORG_NAME = 'esy-ocaml-test'
NPM_SCOPE = 'opam'

OPAM_PACKAGES = os.path.join(os.path.dirname(__file__), '..', 'opam-repository', 'packages')

OPAM_PACKAGES_BLACKLIST = {
    "camlp4.4.03+system",
    "camlp4.4.02+system",
    "camlp4.4.04+system",
    "inotify.2.2", # doesn't support mac
    "inotify.2.3",
    "ocaml-data-notation.0.0.9",
    "lwt.2.6.0", # temp
    "ppx_tools.5.0+4.03.0"
    }

ESY_EXTRA_DEP = {
    "camomile": ['cppo', 'camlp4']
}

OPAM_DEPOPT_BLACKLIST = {
    "conf-libev",
    "lablgtk",
    "ssl",
    "mirage-xen-ocaml",
    "tyxml",
    "reactiveData",
    "deriving"
    }

GH_USER = os.environ.get('GH_USER', '')
GH_TOKEN = os.environ.get('GH_TOKEN', '')

cleanup = '(make clean || true)'
opam_install = '(opam-installer --prefix=$cur__install || true)'

drop_beta_from_version = lambda version: version.replace('-beta', '')

OVERRIDE = {
    'ocp-build': {
        'version': drop_beta_from_version
    },
    'typerex-build': {
        'version': drop_beta_from_version,
        "build": [
            "(cd $cur__root/tools/ocp-autoconf/skeleton && mv .npmignore .gitignore)",
            "(cd $cur__root/tools/ocp-autoconf/skeleton/autoconf && mv .npmignore .gitignore)",
            "./configure --prefix $cur__install",
            "make",
            "make install",
            "(opam-installer --prefix=$cur__install || true)"
        ],
    },
    'ocamlbuild': {
        'build': 'true',
    },
    'ocamlfind': {
        'build': [
            cleanup,
            './configure -bindir $cur__bin -sitelib $cur__lib -mandir $cur__man -config $cur__lib/findlib.conf -no-custom -no-topfind -no-camlp4',
            'make all',
            'make opt',
            'make install',
            opam_install
        ],
    },
    'cppo': {
        'build': [
            cleanup,
            'make all',
            'make opt',
            'make ocamlbuild',
            'make LIBDIR=$cur__lib install-lib',
            'make BINDIR=$cur__bin install-bin',
            opam_install
        ],
    },
    'lwt': {
        'build': [
            cleanup,
            "mkdir -p src/unix/jobs-unix",
            "./configure --prefix $cur__install --${conf_libev_enable:-disable}-libev --${camlp4_enable:-disable}-camlp4 --${react_enable:-disable}-react --${ssl_enable:-disable}-ssl --${base_unix_enable:-disable}-unix --${base_threads_enable:-disable}-preemptive --${lablgtk_enable:-disable}-glib --${ppx_tools_enable:-disable}-ppx",
            "make build",
            "make install",
            opam_install
        ],
        'exportedEnv': {
            'CAML_LD_LIBRARY_PATH': {
                'scope': 'global',
                'val': '$opam_lwt__lib/lwt:$CAML_LD_LIBRARY_PATH',
            }
        }
    },
    'lambda-term': {
        'exportedEnv': {
            'CAML_LD_LIBRARY_PATH': {
                'scope': 'global',
                'val': '$opam_lambda_term__lib/lambda-term:$CAML_LD_LIBRARY_PATH',
            }
        }
    },
    'bin_prot': {
        'exportedEnv': {
            'CAML_LD_LIBRARY_PATH': {
                'scope': 'global',
                'val': '$opam_bin_prot__lib/stublibs:$CAML_LD_LIBRARY_PATH',
            }
        }
    },
    'core_kernel': {
        'exportedEnv': {
            'CAML_LD_LIBRARY_PATH': {
                'scope': 'global',
                'val': '$opam_core_kernel__lib/stublibs:$CAML_LD_LIBRARY_PATH',
            }
        }
    },
    'core': {
        'exportedEnv': {
            'CAML_LD_LIBRARY_PATH': {
                'scope': 'global',
                'val': '$opam_core__lib/stublibs:$CAML_LD_LIBRARY_PATH',
            }
        }
    },
    'async_extra': {
        'exportedEnv': {
            'CAML_LD_LIBRARY_PATH': {
                'scope': 'global',
                'val': '$opam_async_extra__lib/stublibs:$CAML_LD_LIBRARY_PATH',
            }
        }
    },
    'jenga': {
        'exportedEnv': {
            'CAML_LD_LIBRARY_PATH': {
                'scope': 'global',
                'val': '$opam_jenga__lib/stublibs:$CAML_LD_LIBRARY_PATH',
            }
        }
    },
    're2': {
        'exportedEnv': {
            'CAML_LD_LIBRARY_PATH': {
                'scope': 'global',
                'val': '$opam_re2__lib/stublibs:$CAML_LD_LIBRARY_PATH',
            }
        }
    },
    'ppx_expect': {
        'exportedEnv': {
            'CAML_LD_LIBRARY_PATH': {
                'scope': 'global',
                'val': '$opam_ppx_expect__lib/stublibs:$CAML_LD_LIBRARY_PATH',
            }
        }
    },
    'ocaml_plugin': {
        'exportedEnv': {
            'CAML_LD_LIBRARY_PATH': {
                'scope': 'global',
                'val': '$opam_ocaml_plugin__lib/stublibs:$CAML_LD_LIBRARY_PATH',
            }
        }
    },
    'async_unix': {
        'exportedEnv': {
            'CAML_LD_LIBRARY_PATH': {
                'scope': 'global',
                'val': '$opam_async_unix__lib/stublibs:$CAML_LD_LIBRARY_PATH',
            }
        }
    },
    'ocamlgraph': {
        'exclude_dependencies': {'conf-gnomecanvas'},
    },
    'utop': {
        'exclude_dependencies': {'camlp4'},
    },
}

def is_dep_allowed(name, dep):
    return not (dep in OVERRIDE.get(name, {}).get('exclude_dependencies', set()))
