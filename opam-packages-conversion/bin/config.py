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

def export_caml_ld_library_path(name):
    return {
        'exportedEnv': {
            'CAML_LD_LIBRARY_PATH': caml_ld_library_path(name),
        }
    }

def caml_ld_library_path(name):
    name = name.replace('-', '_')
    return {
        'scope': 'global',
        'val': '$opam_%s__lib/%s:$CAML_LD_LIBRARY_PATH' % (name, name),
    }

OVERRIDE = {
    'ocp-build': {
        'version': drop_beta_from_version
    },
    'conf-gmp': {
        'build': [
          'cc -c $CFLAGS -I/usr/local/include test.c'
        ]
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
    'ctypes': export_caml_ld_library_path('ctypes'),
    'zarith': export_caml_ld_library_path('zarith'),
    'cstruct': export_caml_ld_library_path('cstruct'),
    'launchd': export_caml_ld_library_path('launchd'),
    'lwt': export_caml_ld_library_path('lwt'),
    'lambda-term': export_caml_ld_library_path('lambda-term'),
    'bin_prot': export_caml_ld_library_path('bin_prot'),
    'core_kernel': export_caml_ld_library_path('core_kernel'),
    'core': export_caml_ld_library_path('core'),
    'async_extra': export_caml_ld_library_path('async_extra'),
    'async_ssl': export_caml_ld_library_path('async_ssl'),
    'jenga': export_caml_ld_library_path('jenga'),
    're2': export_caml_ld_library_path('re2'),
    'ppx_expect': export_caml_ld_library_path('ppx_expect'),
    'ocaml_plugin': export_caml_ld_library_path('ocaml_plugin'),
    'async_unix': export_caml_ld_library_path('async_unix'),
    'inotify': export_caml_ld_library_path('inotify'),
    'io-page': export_caml_ld_library_path('io-page'),
    'mtime': export_caml_ld_library_path('mtime'),
    'nocrypto': export_caml_ld_library_path('nocrypto'),
    'pcre': export_caml_ld_library_path('pcre'),
    'ppx_expect': export_caml_ld_library_path('ppx_expect'),
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
        'exclude_dependencies': {'xen-evtchn', 'xen-gnt'},
        'exportedEnv': {
            'CAML_LD_LIBRARY_PATH': caml_ld_library_path('vchan'),
        }
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
