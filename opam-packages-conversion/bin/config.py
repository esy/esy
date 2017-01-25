import os.path

__dir__ = os.path.dirname(os.path.realpath(__file__))

os.environ['PATH'] = '%s:%s' % (__dir__, os.environ['PATH'])

GH_ORG_NAME = 'esy-ocaml'
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
    "mirage-xen",
    "mirage-xen-ocaml",
    "tyxml",
    "reactiveData",
    "deriving",
    "ocamlbuild",
    "js_of_ocaml",
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
            "./configure --prefix $cur__install",
            "make",
            "make install",
            "(opam-installer --prefix=$cur__install || true)"
        ],
    },
    'ocamlbuild': {
        'build': 'true',
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
    'cohttp': {
        'exclude_dependencies': {'mirage-net'},
    },
    'conduit': {
        'exclude_dependencies': {'mirage-dns'},
    },
    'ocamlgraph': {
        'exclude_dependencies': {'conf-gnomecanvas'},
    },
    'utop': {
        'exclude_dependencies': {'camlp4'},
    },
    'vchan': {
        'exclude_dependencies': {'xen-evtchn', 'xen-gnt'}
    },
    'nocrypto': {
        'exclude_dependencies': {'mirage-xen', 'mirage-entropy-xen', 'zarith-xen'}
    },
    'mtime': {
        'exclude_dependencies': {'js_of_ocaml'}
    },
}

def is_dep_allowed(name, dep):
    if dep == 'ocamlbuild':
        return False
    return not (dep in OVERRIDE.get(name, {}).get('exclude_dependencies', set()))
