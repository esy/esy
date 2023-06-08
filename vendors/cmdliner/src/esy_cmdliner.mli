(*---------------------------------------------------------------------------
   Copyright (c) 2011 Daniel C. Bünzli. All rights reserved.
   Distributed under the ISC license, see terms at the end of the file.
   %%NAME%% %%VERSION%%
  ---------------------------------------------------------------------------*)

(** Declarative definition of command line interfaces.

    [Esy_cmdliner] provides a simple and compositional mechanism
    to convert command line arguments to OCaml values and pass them to
    your functions. The module automatically handles syntax errors,
    help messages and UNIX man page generation. It supports programs
    with single or multiple commands
    (like [darcs] or [git]) and respect most of the
    {{:http://www.opengroup.org/onlinepubs/009695399/basedefs/xbd_chap12.html}
    POSIX} and
    {{:http://www.gnu.org/software/libc/manual/html_node/Argument-Syntax.html}
    GNU} conventions.

    Consult the {{!basics}basics}, details about the supported
    {{!cmdline}command line syntax} and {{!examples} examples} of
    use. Open the module to use it, it defines only three modules in
    your scope.

    {e %%VERSION%% — {{:%%PKG_HOMEPAGE%% }homepage}} *)

(** {1:top Interface} *)

(** Man page specification.

    Man page generation is automatically handled by [Esy_cmdliner],
    consult the {{!manual}details}.

    The {!block} type is used to define a man page's content. It's a
    good idea to follow the {{!standard_sections}standard} manual page
    structure.

   {b References.}
   {ul
   {- [man-pages(7)], {{:http://man7.org/linux/man-pages/man7/man-pages.7.html}
      {e Conventions for writing Linux man pages}}.}} *)
module Manpage : sig

  (** {1:man Man pages} *)

  type block =
    [ `S of string | `P of string | `Pre of string | `I of string * string
    | `Noblank | `Blocks of block list ]
  (** The type for a block of man page text.

      {ul
      {- [`S s] introduces a new section [s], see the
         {{!standard_sections}standard section names}.}
      {- [`P t] is a new paragraph with text [t].}
      {- [`Pre t] is a new preformatted paragraph with text [t].}
      {- [`I (l,t)] is an indented paragraph with label
         [l] and text [t].}
      {- [`Noblank] suppresses the blank line introduced between two blocks.}
      {- [`Blocks bs] splices the blocks [bs].}}

      Except in [`Pre], whitespace and newlines are not significant
      and are all collapsed to a single space. All block strings
      support the {{!doclang}documentation markup language}.*)

  val escape : string -> string
  (** [escape s] escapes [s] so that it doesn't get interpreted by the
      {{!doclang}documentation markup language}. *)

  type title = string * int * string * string * string
  (** The type for man page titles. Describes the man page
      [title], [section], [center_footer], [left_footer], [center_header]. *)

  type t = title * block list
  (** The type for a man page. A title and the page text as a list of blocks. *)

  type xref =
    [ `Main | `Cmd of string | `Tool of string | `Page of string * int ]
  (** The type for man page cross-references.
      {ul
      {- [`Main] refers to the man page of the program itself.}
      {- [`Cmd cmd] refers to the man page of the program's [cmd]
         command (which must exist).}
      {- [`Tool bin] refers to the command line tool named [bin].}
      {- [`Page (name, sec)] refers to the man page [name(sec)].}} *)

  (** {1:standard_sections Standard section names and content}

      The following are standard man page section names, roughly ordered
      in the order they conventionally appear. See also
      {{:http://man7.org/linux/man-pages/man7/man-pages.7.html}[man man-pages]}
      for more elaborations about what sections should contain. *)

  val s_name : string
  (** The [NAME] section. This section is automatically created by
      [Esy_cmdliner] for your. *)

  val s_synopsis : string
  (** The [SYNOPSIS] section. By default this section is automatically
      created by [Esy_cmdliner] for you, unless it is the first section of
      your term's man page, in which case it will replace it with yours. *)

  val s_description : string
  (** The [DESCRIPTION] section. This should be a description of what
      the tool does and provide a little bit of usage and
      documentation guidance. *)

  val s_commands : string
  (** The [COMMANDS] section. By default subcommands get listed here. *)

  val s_arguments : string
  (** The [ARGUMENTS] section. By default positional arguments get
      listed here. *)

  val s_options : string
  (** The [OPTIONS] section. By default options and flag arguments get
      listed here. *)

  val s_common_options : string
  (** The [COMMON OPTIONS] section. For programs with multiple commands
      a section that can be used to gather options common to all commands. *)

  val s_exit_status : string
  (** The [EXIT STATUS] section. By default term status exit codes
      get listed here. *)

  val s_environment : string
  (** The [ENVIRONMENT] section. By default environment variables get
      listed here. *)

  val s_environment_intro : block
  (** [s_environment_intro] is the introduction content used by cmdliner
      when it creates the {!s_environment} section. *)

  val s_files : string
  (** The [FILES] section. *)

  val s_bugs : string
  (** The [BUGS] section. *)

  val s_examples : string
  (** The [EXAMPLES] section. *)

  val s_authors : string
  (** The [AUTHORS] section. *)

  val s_see_also : string
  (** The [SEE ALSO] section. *)

  (** {1:output Output}

    The {!print} function can be useful if the client wants to define
    other man pages (e.g. to implement a help command). *)

  type format = [ `Auto | `Pager | `Plain | `Groff ]
  (** The type for man page output specification.
      {ul
      {- [`Auto], formats like [`Pager] or [`Plain] whenever the [TERM]
         environment variable is [dumb] or unset.}
      {- [`Pager], tries to write to a discovered pager, if that fails
         uses the [`Plain] format.}
      {- [`Plain], formats to plain text.}
      {- [`Groff], formats to groff commands.}} *)

  val print :
    ?errs:Format.formatter ->
    ?subst:(string -> string option) -> format -> Format.formatter -> t -> unit
  (** [print ~errs ~subst fmt ppf page] prints [page] on [ppf] in the
      format [fmt]. [subst] can be used to perform variable
      substitution,(defaults to the identity). [errs] is used to print
      formatting errors, it defaults to {!Format.err_formatter}. *)
end

(** Terms.

    A term is evaluated by a program to produce a {{!result}result},
    which can be turned into an {{!exits}exit status}. A term made of terms
    referring to {{!Arg}command line arguments} implicitly defines a
    command line syntax. *)
module Term : sig

  (** {1:terms Terms} *)

  type +'a t
  (** The type for terms evaluating to values of type 'a. *)

  val const : 'a -> 'a t
  (** [const v] is a term that evaluates to [v]. *)

  (**/**)
  val pure : 'a -> 'a t
  (** @deprecated use {!const} instead. *)

  val man_format : Manpage.format t
  (** @deprecated Use {!Arg.man_format} instead. *)
  (**/**)

  val ( $ ) : ('a -> 'b) t -> 'a t -> 'b t
  (** [f $ v] is a term that evaluates to the result of applying
      the evaluation of [v] to the one of [f]. *)

  val app : ('a -> 'b) t -> 'a t -> 'b t
  (** [app] is {!($)}. *)

  (** {1 Interacting with Esy_cmdliner's evaluation} *)

  type 'a ret =
    [ `Help of Manpage.format * string option
    | `Error of (bool * string)
    | `Ok of 'a ]
  (** The type for command return values. See {!ret}. *)

  val ret : 'a ret t -> 'a t
  (** [ret v] is a term whose evaluation depends on the case
      to which [v] evaluates. With :
      {ul
      {- [`Ok v], it evaluates to [v].}
      {- [`Error (usage, e)], the evaluation fails and [Esy_cmdliner] prints
         the error [e] and the term's usage if [usage] is [true].}
      {- [`Help (format, name)], the evaluation fails and [Esy_cmdliner] prints the
         term's man page in the given [format] (or the man page for a
         specific [name] term in case of multiple term evaluation).}}   *)

  val term_result : ?usage:bool -> ('a, [`Msg of string]) result t -> 'a t
  (** [term_result ~usage t] evaluates to
      {ul
      {- [`Ok v] if [t] evaluates to [Ok v]}
      {- [`Error `Term] with the error message [e] and usage shown according
         to [usage] (defaults to [false]), if [t] evaluates to
         [Error (`Msg e)].}} *)

  val cli_parse_result : ('a, [`Msg of string]) result t -> 'a t
  (** [cli_parse_result t] is a term that evaluates to:
      {ul
      {- [`Ok v] if [t] evaluates to [Ok v].}
      {- [`Error `Parse] with the error message [e]
         if [t] evaluates to [Error (`Msg e)].}} *)

  val main_name : string t
  (** [main_name] is a term that evaluates to the "main" term's name. *)

  val choice_names : string list t
  (** [choice_names] is a term that evaluates to the names of the terms
      to choose from. *)

  val with_used_args : 'a t -> ('a * string list) t
  (** [with_used_args t] is a term that evaluates to [t] tupled
      with the arguments from the command line that where used to
      evaluate [t]. *)

  (** {1:tinfo Term information}

      Term information defines the name and man page of a term.
      For simple evaluation this is the name of the program and its
      man page. For multiple term evaluation, this is
      the name of a command and its man page. *)

  type exit_info
  (** The type for exit status information. *)

  val exit_info : ?docs:string -> ?doc:string -> ?max:int -> int -> exit_info
  (** [exit_info ~docs ~doc min ~max] describe the range of exit
      statuses from [min] to [max] (defaults to [min]). [doc] is the
      man page information for the statuses, defaults to ["undocumented"].
      [docs] is the title of the man page section in which the statuses
      will be listed, it defaults to {!Manpage.s_exit_status}.

      In [doc] the {{!doclang}documentation markup language} can be
      used with following variables:
      {ul
      {- [$(status)], the value of [min].}
      {- [$(status_max)], the value of [max].}
      {- The variables mentioned in {!info}}} *)

  val default_exits : exit_info list
  (** [default_exits] is information for exit status {!exit_status_success}
      added to {!default_error_exits}. *)

  val default_error_exits : exit_info list
  (** [default_error_exits] is information for exit statuses
      {!exit_status_cli_error} and {!exit_status_internal_error}. *)

  type env_info
  (** The type for environment variable information. *)

  val env_info : ?docs:string -> ?doc:string -> string -> env_info
  (** [env_info ~docs ~doc var] describes an environment variable
      [var]. [doc] is the man page information of the environment
      variable, defaults to ["undocumented"]. [docs] is the title of
      the man page section in which the environment variable will be
      listed, it defaults to {!Manpage.s_environment}.

      In [doc] the {{!doclang}documentation markup language} can be
      used with following variables:
      {ul
      {- [$(env)], the value of [var].}
      {- The variables mentioned in {!info}}} *)

  type info
  (** The type for term information. *)

  val info :
    ?man_xrefs:Manpage.xref list -> ?man:Manpage.block list ->
    ?envs:env_info list -> ?exits:exit_info list -> ?sdocs:string ->
    ?docs:string -> ?doc:string -> ?version:string -> ?stop_on_pos:bool -> string -> info
  (** [info sdocs man docs doc version name] is a term information
      such that:
      {ul
      {- [name] is the name of the program or the command.}
      {- [version] is the version string of the program, ignored
         for commands.}
      {- [doc] is a one line description of the program or command used
         for the [NAME] section of the term's man page. For commands this
         description is also used in the list of commands of the main
         term's man page.}
      {- [docs], only for commands, the title of the section of the main
         term's man page where it should be listed (defaults to
         {!Manpage.s_commands}).}
      {- [sdocs] defines the title of the section in which the
         standard [--help] and [--version] arguments are listed
         (defaults to {!Manpage.s_options}).}
      {- [exits] is a list of exit statuses that the term evaluation
         may produce.}
      {- [envs] is a list of environment variables that influence
         the term's evaluation.}
      {- [man] is the text of the man page for the term.}
      {- [man_xrefs] are cross-references to other manual pages. These
         are used to generate a {!Manpage.s_see_also} section.}}
      [doc], [man], [envs] support the {{!doclang}documentation markup
      language} in which the following variables are recognized:
      {ul
      {- [$(tname)] the term's name.}
      {- [$(mname)] the main term's name.}} *)

  val name : info -> string
  (** [name ti] is the name of the term information. *)

 (** {1:evaluation Evaluation} *)

  type 'a result =
    [ `Ok of 'a | `Error of [`Parse | `Term | `Exn ] | `Version | `Help ]
  (** The type for evaluation results.
      {ul
      {- [`Ok v], the term evaluated successfully and [v] is the result.}
      {- [`Version], the version string of the main term was printed
       on the help formatter.}
      {- [`Help], man page about the term was printed on the help formatter.}
      {- [`Error `Parse], a command line parse error occurred and was
         reported on the error formatter.}
      {- [`Error `Term], a term evaluation error occurred and was reported
         on the error formatter (see {!Term.ret}).}
      {- [`Error `Exn], an exception [e] was caught and reported
         on the error formatter (see the [~catch] parameter of {!eval}).}} *)

  val eval :
    ?help:Format.formatter -> ?err:Format.formatter -> ?catch:bool ->
    ?env:(string -> string option) -> ?argv:string array -> ('a t * info) ->
    'a result
  (** [eval help err catch argv (t,i)]  is the evaluation result
      of [t] with command line arguments [argv] (defaults to {!Sys.argv}).

      If [catch] is [true] (default) uncaught exceptions
      are intercepted and their stack trace is written to the [err]
      formatter.

      [help] is the formatter used to print help or version messages
      (defaults to {!Format.std_formatter}). [err] is the formatter
      used to print error messages (defaults to {!Format.err_formatter}).

      [env] is used for environment variable lookup, the default
      uses {!Sys.getenv}. *)

  val eval_choice :
    ?help:Format.formatter -> ?err:Format.formatter -> ?catch:bool -> ?main_on_err:bool ->
    ?env:(string -> string option) -> ?argv:string array ->
    'a t * info -> ('a t * info) list -> 'a result
  (** [eval_choice help err catch argv (t,i) choices] is like {!eval}
      except that if the first argument on the command line is not an option
      name it will look in [choices] for a term whose information has this
      name and evaluate it.

      If the command name is unknown an error is reported. If the name
      is unspecified the "main" term [t] is evaluated. [i] defines the
      name and man page of the program. *)

  val eval_peek_opts :
    ?version_opt:bool -> ?env:(string -> string option) ->
    ?argv:string array -> 'a t -> 'a option * 'a result
  (** [eval_peek_opts version_opt argv t] evaluates [t], a term made
      of optional arguments only, with the command line [argv]
      (defaults to {!Sys.argv}). In this evaluation, unknown optional
      arguments and positional arguments are ignored.

      The evaluation returns a pair. The first component is
      the result of parsing the command line [argv] stripped from
      any help and version option if [version_opt] is [true] (defaults
      to [false]). It results in:
      {ul
      {- [Some _] if the command line would be parsed correctly given the
         {e partial} knowledge in [t].}
      {- [None] if a parse error would occur on the options of [t]}}

      The second component is the result of parsing the command line
      [argv] without stripping the help and version options. It
      indicates what the evaluation would result in on [argv] given
      the partial knowledge in [t] (for example it would return
      [`Help] if there's a help option in [argv]). However in
      contrasts to {!eval} and {!eval_choice} no side effects like
      error reporting or help output occurs.

      {b Note.} Positional arguments can't be peeked without the full
      specification of the command line: we can't tell apart a
      positional argument from the value of an unknown optional
      argument.  *)

  (** {1:exits Turning evaluation results into exit codes}

      {b Note.} If you are using the following functions to handle
      the evaluation result of a term you should add {!default_exits} to
      the term's information {{!info}[~exits]} argument.

      {b WARNING.} You should avoid status codes strictly greater than 125
      as those may be used by
      {{:https://www.gnu.org/software/bash/manual/html_node/Exit-Status.html}
       some} shells. *)

  val exit_status_success : int
  (** [exit_status_success] is 0, the exit status for success. *)

  val exit_status_cli_error : int
  (** [exit_status_cli_error] is 124, an exit status for command line
      parsing errors. *)

  val exit_status_internal_error : int
  (** [exit_status_internal_error] is 125, an exit status for unexpected
      internal errors. *)

  val exit_status_of_result : ?term_err:int -> 'a result -> int
  (** [exit_status_of_result ~term_err r] is an [exit(3)] status
      code determined from [r] as follows:
      {ul
      {- {!exit_status_success} if [r] is one of [`Ok _], [`Version], [`Help]}
      {- [term_err] if [r] is [`Error `Term], [term_err] defaults to [1].}
      {- {!exit_status_cli_error} if [r] is [`Error `Parse]}
      {- {!exit_status_internal_error} if [r] is [`Error `Exn]}} *)

  val exit_status_of_status_result : ?term_err:int -> int result -> int
  (** [exit_status_of_status_result] is like {!exit_status_of_result}
      except for [`Ok n] where [n] is used as the status exit code. *)

  val exit : ?term_err:int -> 'a result -> unit
  (** [exit ~term_err r] is
      [Pervasives.exit @@ exit_status_of_result ~term_err r] *)

  val exit_status : ?term_err:int -> int result -> unit
  (** [exit_status ~term_err r] is
      [Pervasives.exit @@ exit_status_of_status_result ~term_err r] *)
end

(** Terms for command line arguments.

    This module provides functions to define terms that evaluate
    to the arguments provided on the command line.

    Basic constraints, like the argument type or repeatability, are
    specified by defining a value of type {!t}. Further constraints can
    be specified during the {{!argterms}conversion} to a term. *)
module Arg : sig

(** {1:argconv Argument converters}

    An argument converter transforms a string argument of the command
    line to an OCaml value. {{!converters}Predefined converters}
    are provided for many types of the standard library. *)

  type 'a parser = string -> [ `Ok of 'a | `Error of string ]
  (** The type for argument parsers.

      @deprecated Use a parser with [('a, [ `Msg of string]) result] results
      and {!conv}. *)

  type 'a printer = Format.formatter -> 'a -> unit
  (** The type for converted argument printers. *)

  type 'a conv = 'a parser * 'a printer
  (** The type for argument converters.

      {b WARNING.} This type will become abstract in the next
      major version of cmdliner, use {!val:conv} or {!pconv}
      to construct values of this type. *)

  type 'a converter = 'a conv
  (** @deprecated Use the {!type:conv} type via the {!val:conv} and {!pconv}
      functions. *)

  val conv :
    ?docv:string -> (string -> ('a, [`Msg of string]) result) * 'a printer ->
    'a conv
  (** [converter ~docv (parse, print)] is an argument converter
      parsing values with [parse] and printing them with
      [print]. [docv] is a documentation meta-variable used in the
      documentation to stand for the argument value, defaults to
      ["VALUE"]. *)

  val pconv :
    ?docv:string -> 'a parser * 'a printer -> 'a conv
  (** [pconv] is like {!converter}, but uses a deprecated {!parser}
      signature. *)

  val conv_parser : 'a conv -> (string -> ('a, [`Msg of string]) result)
  (** [conv_parser c] 's [c]'s parser. *)

  val conv_printer : 'a conv -> 'a printer
  (** [conv_printer c] is [c]'s printer. *)

  val conv_docv : 'a conv -> string
  (** [conv_docv c] is [c]'s documentation meta-variable.

      {b WARNING.} Currently always returns ["VALUE"] in the future
      will return the value given to {!conv} or {!pconv}. *)

  val parser_of_kind_of_string :
    kind:string -> (string -> 'a option) ->
    (string -> ('a, [`Msg of string]) result)
  (** [parser_of_kind_of_string ~kind kind_of_string] is an argument
      parser using the [kind_of_string] function for parsing and [kind]
      to report errors (e.g. could be ["an integer"] for an [int] parser.). *)

  val some : ?none:string -> 'a conv -> 'a option conv
  (** [some none c] is like the converter [c] except it returns
      [Some] value. It is used for command line arguments
      that default to [None] when absent. [none] is what to print to
      document the absence (defaults to [""]). *)

(** {1:arginfo Arguments and their information}

    Argument information defines the man page information of an
    argument and, for optional arguments, its names. An environment
    variable can also be specified to read the argument value from
    if the argument is absent from the command line and the variable
    is defined. *)

  type env = Term.env_info
  (** The type for environment variables and their documentation. *)

  val env_var : ?docs:string -> ?doc:string -> string -> env
  (** [env_var docs doc var] is an environment variables [var]. [doc]
      is the man page information of the environment variable, the
      {{!doclang}documentation markup language} with the  variables
      mentioned in {!info} be used; it defaults to ["See option
      $(opt)."].  [docs] is the title of the man page section in which
      the environment variable will be listed, it defaults to
      {!Manpage.s_environment}. *)

  type 'a t
  (** The type for arguments holding data of type ['a]. *)

  type info
  (** The type for information about command line arguments. *)

  val info :
    ?docs:string -> ?docv:string -> ?doc:string -> ?env:env -> string list ->
    info
  (** [info docs docv doc env names] defines information for
      an argument.
      {ul
      {- [names] defines the names under which an optional argument
         can be referred to. Strings of length [1] (["c"]) define
         short option names (["-c"]), longer strings (["count"])
         define long option names (["--count"]). [names] must be empty
         for positional arguments.}
      {- [env] defines the name of an environment variable which is
         looked up for defining the argument if it is absent from the
         command line. See {{!envlookup}environment variables} for
         details.}
      {- [doc] is the man page information of the argument.
         The {{!doclang}documentation language} can be used and
         the following variables are recognized:
         {ul
         {- ["$(docv)"] the value of [docv] (see below).}
         {- ["$(opt)"], one of the options of [names], preference
            is given to a long one.}
         {- ["$(env)"], the environment var specified by [env] (if any).}}
         {{!doc_helpers}These functions} can help with formatting argument
         values.}
      {- [docv] is for positional and non-flag optional arguments.
         It is a variable name used in the man page to stand for their value.}
      {- [docs] is the title of the man page section in which the argument
         will be listed. For optional arguments this defaults
         to {!Manpage.s_options}. For positional arguments this defaults
         to {!Manpage.s_arguments}. However a positional argument is only
         listed if it has both a [doc] and [docv] specified.}} *)

  val ( & ) : ('a -> 'b) -> 'a -> 'b
  (** [f & v] is [f v], a right associative composition operator for
      specifying argument terms. *)

(** {1:optargs Optional arguments}

    The information of an optional argument must have at least
    one name or [Invalid_argument] is raised. *)

  val flag : info -> bool t
  (** [flag i] is a [bool] argument defined by an optional flag
      that may appear {e at most} once on the command line under one of
      the names specified by [i]. The argument holds [true] if the
      flag is present on the command line and [false] otherwise. *)

  val flag_all : info -> bool list t
  (** [flag_all] is like {!flag} except the flag may appear more than
      once. The argument holds a list that contains one [true] value per
      occurrence of the flag. It holds the empty list if the flag
      is absent from the command line. *)

  val vflag : 'a -> ('a * info) list -> 'a t
  (** [vflag v \[v]{_0}[,i]{_0}[;...\]] is an ['a] argument defined
      by an optional flag that may appear {e at most} once on
      the command line under one of the names specified in the [i]{_k}
      values. The argument holds [v] if the flag is absent from the
      command line and the value [v]{_k} if the name under which it appears
      is in [i]{_k}.

      {b Note.} Environment variable lookup is unsupported for
      for these arguments. *)

  val vflag_all : 'a list -> ('a * info) list -> 'a list t
  (** [vflag_all v l] is like {!vflag} except the flag may appear more
      than once. The argument holds the list [v] if the flag is absent
      from the command line. Otherwise it holds a list that contains one
      corresponding value per occurrence of the flag, in the order found on
      the command line.

      {b Note.} Environment variable lookup is unsupported for
      for these arguments. *)

  val opt : ?vopt:'a -> 'a conv -> 'a -> info -> 'a t
  (** [opt vopt c v i] is an ['a] argument defined by the value of
      an optional argument that may appear {e at most} once on the command
      line under one of the names specified by [i]. The argument holds
      [v] if the option is absent from the command line. Otherwise
      it has the value of the option as converted by [c].

      If [vopt] is provided the value of the optional argument is itself
      optional, taking the value [vopt] if unspecified on the command line. *)

  val opt_all : ?vopt:'a -> 'a conv -> 'a list -> info -> 'a list t
  (** [opt_all vopt c v i] is like {!opt} except the optional argument may
      appear more than once. The argument holds a list that contains one value
      per occurrence of the flag in the order found on the command line.
      It holds the list [v] if the flag is absent from the command line. *)

  (** {1:posargs Positional arguments}

      The information of a positional argument must have no name
      or [Invalid_argument] is raised. Positional arguments indexing
      is zero-based.

      {b Warning.} The following combinators allow to specify and
      extract a given positional argument with more than one term.
      This should not be done as it will likely confuse end users and
      documentation generation. These over-specifications may be
      prevented by raising [Invalid_argument] in the future. But for now
      it is the client's duty to make sure this doesn't happen. *)

  val pos : ?rev:bool -> int -> 'a conv -> 'a -> info -> 'a t
  (** [pos rev n c v i] is an ['a] argument defined by the [n]th
      positional argument of the command line as converted by [c].
      If the positional argument is absent from the command line
      the argument is [v].

      If [rev] is [true] (defaults to [false]), the computed
      position is [max-n] where [max] is the position of
      the last positional argument present on the command line. *)

  val pos_all : 'a conv -> 'a list -> info -> 'a list t
  (** [pos_all c v i] is an ['a list] argument that holds
      all the positional arguments of the command line as converted
      by [c] or [v] if there are none. *)

  val pos_left :
    ?rev:bool -> int -> 'a conv -> 'a list -> info -> 'a list t
  (** [pos_left rev n c v i] is an ['a list] argument that holds
      all the positional arguments as converted by [c] found on the left
      of the [n]th positional argument or [v] if there are none.

      If [rev] is [true] (defaults to [false]), the computed
      position is [max-n] where [max] is the position of
      the last positional argument present on the command line. *)

  val pos_right :
    ?rev:bool -> int -> 'a conv -> 'a list -> info -> 'a list t
  (** [pos_right] is like {!pos_left} except it holds all the positional
      arguments found on the right of the specified positional argument. *)

  (** {1:argterms Arguments as terms} *)

  val value : 'a t -> 'a Term.t
  (** [value a] is a term that evaluates to [a]'s value. *)

  val required : 'a option t -> 'a Term.t
  (** [required a] is a term that fails if [a]'s value is [None] and
      evaluates to the value of [Some] otherwise. Use this for required
      positional arguments (it can also be used for defining required
      optional arguments, but from a user interface perspective this
      shouldn't be done, it is a contradiction in terms). *)

  val non_empty : 'a list t -> 'a list Term.t
  (** [non_empty a] is term that fails if [a]'s list is empty and
      evaluates to [a]'s list otherwise. Use this for non empty lists
      of positional arguments. *)

  val last : 'a list t -> 'a Term.t
  (** [last a] is a term that fails if [a]'s list is empty and evaluates
      to the value of the last element of the list otherwise. Use this
      for lists of flags or options where the last occurrence takes precedence
      over the others. *)

  (** {1:predef Predefined arguments} *)

  val man_format : Manpage.format Term.t
  (** [man_format] is a term that defines a [--man-format] option and
      evaluates to a value that can be used with {!Manpage.print}. *)

  (** {1:converters Predefined converters} *)

  val bool : bool conv
  (** [bool] converts values with {!bool_of_string}. *)

  val char : char conv
  (** [char] converts values by ensuring the argument has a single char. *)

  val int : int conv
  (** [int] converts values with {!int_of_string}. *)

  val nativeint : nativeint conv
  (** [nativeint] converts values with {!Nativeint.of_string}. *)

  val int32 : int32 conv
  (** [int32] converts values with {!Int32.of_string}. *)

  val int64 : int64 conv
  (** [int64] converts values with {!Int64.of_string}. *)

  val float : float conv
  (** [float] converts values with {!float_of_string}. *)

  val string : string conv
  (** [string] converts values with the identity function. *)

  val enum : (string * 'a) list -> 'a conv
  (** [enum l p] converts values such that unambiguous prefixes of string names
      in [l] map to the corresponding value of type ['a].

      {b Warning.} The type ['a] must be comparable with {!Pervasives.compare}.

      @raise Invalid_argument if [l] is empty. *)

  val file : string conv
  (** [file] converts a value with the identity function and
      checks with {!Sys.file_exists} that a file with that name exists. *)

  val dir : string conv
  (** [dir] converts a value with the identity function and checks
      with {!Sys.file_exists} and {!Sys.is_directory}
      that a directory with that name exists. *)

  val non_dir_file : string conv
  (** [non_dir_file] converts a value with the identity function and checks
      with {!Sys.file_exists} and {!Sys.is_directory}
      that a non directory file with that name exists. *)

  val list : ?sep:char -> 'a conv -> 'a list conv
  (** [list sep c] splits the argument at each [sep] (defaults to [','])
      character and converts each substrings with [c]. *)

  val array : ?sep:char -> 'a conv -> 'a array conv
  (** [array sep c] splits the argument at each [sep] (defaults to [','])
      character and converts each substring with [c]. *)

  val pair : ?sep:char -> 'a conv -> 'b conv -> ('a * 'b) conv
  (** [pair sep c0 c1] splits the argument at the {e first} [sep] character
      (defaults to [',']) and respectively converts the substrings with
      [c0] and [c1]. *)

  val t2 : ?sep:char -> 'a conv -> 'b conv -> ('a * 'b) conv
  (** {!t2} is {!pair}. *)

  val t3 : ?sep:char -> 'a conv ->'b conv -> 'c conv -> ('a * 'b * 'c) conv
  (** [t3 sep c0 c1 c2] splits the argument at the {e first} two [sep]
      characters (defaults to [',']) and respectively converts the
      substrings with [c0], [c1] and [c2]. *)

  val t4 :
    ?sep:char -> 'a conv -> 'b conv -> 'c conv -> 'd conv ->
    ('a * 'b * 'c * 'd) conv
  (** [t4 sep c0 c1 c2 c3] splits the argument at the {e first} three [sep]
      characters (defaults to [',']) respectively converts the substrings
      with [c0], [c1], [c2] and [c3]. *)

  (** {1:doc_helpers Documentation formatting helpers} *)

  val doc_quote : string -> string
  (** [doc_quote s] quotes the string [s]. *)

  val doc_alts : ?quoted:bool -> string list -> string
  (** [doc_alts alts] documents the alternative tokens [alts] according
      the number of alternatives. If [quoted] is [true] (default)
      the tokens are quoted. The resulting string can be used in
      sentences of the form ["$(docv) must be %s"].

      @raise Invalid_argument if [alts] is the empty string.  *)

  val doc_alts_enum : ?quoted:bool -> (string * 'a) list -> string
  (** [doc_alts_enum quoted alts] is [doc_alts quoted (List.map fst alts)]. *)
end

(** {1:basics Basics}

 With [Esy_cmdliner] your program evaluates a term. A {e term} is a value
 of type {!Term.t}. The type parameter indicates the type of the
 result of the evaluation.

One way to create terms is by lifting regular OCaml values with
{!Term.const}. Terms can be applied to terms evaluating to functional
values with {!Term.( $ )}. For example for the function:

{[
let revolt () = print_endline "Revolt!"
]}

the term :

{[
open Esy_cmdliner

let revolt_t = Term.(const revolt $ const ())
]}

is a term that evaluates to the result (and effect) of the [revolt]
function. Terms are evaluated with {!Term.eval}:

{[
let () = Term.exit @@ Term.eval (revolt_t, Term.info "revolt")
]}

This defines a command line program named ["revolt"], without command
line arguments, that just prints ["Revolt!"] on [stdout].

{[
> ./revolt
Revolt!
]}

The combinators in the {!Arg} module allow to extract command line
argument data as terms. These terms can then be applied to lifted
OCaml functions to be evaluated by the program.

Terms corresponding to command line argument data that are part of a
term evaluation implicitly define a command line syntax.  We show this
on an concrete example.

Consider the [chorus] function that prints repeatedly a given message :

{[
let chorus count msg =
  for i = 1 to count do print_endline msg done
]}

we want to make it available from the command line with the synopsis:

{[
chorus [-c COUNT | --count=COUNT] [MSG]
]}

where [COUNT] defaults to [10] and [MSG] defaults to ["Revolt!"]. We
first define a term corresponding to the [--count] option:

{[
let count =
  let doc = "Repeat the message $(docv) times." in
  Arg.(value & opt int 10 & info ["c"; "count"] ~docv:"COUNT" ~doc)
]}

This says that [count] is a term that evaluates to the value of an
optional argument of type [int] that defaults to [10] if unspecified
and whose option name is either [-c] or [--count]. The arguments [doc]
and [docv] are used to generate the option's man page information.

The term for the positional argument [MSG] is:

{[
let msg =
  let doc = "Overrides the default message to print." in
  let env = Arg.env_var "CHORUS_MSG" ~doc in
  let doc = "The message to print." in
  Arg.(value & pos 0 string "Revolt!" & info [] ~env ~docv:"MSG" ~doc)
]}

which says that [msg] is a term whose value is the positional argument
at index [0] of type [string] and defaults to ["Revolt!"]  or the
value of the environment variable [CHORUS_MSG] if the argument is
unspecified on the command line. Here again [doc] and [docv] are used
for the man page information.

The term for executing [chorus] with these command line arguments is :

{[
let chorus_t = Term.(const chorus $ count $ msg)
]}

and we are now ready to define our program:

{[
let info =
  let doc = "print a customizable message repeatedly" in
  let man = [
    `S Manpage.s_bugs;
    `P "Email bug reports to <hehey at example.org>." ]
  in
  Term.info "chorus" ~version:"%‌%VERSION%%" ~doc ~exits:Term.default_exits ~man

let () = Term.exit @@ Term.eval (chorus_t, info))
]}

The [info] value created with {!Term.info} gives more information
about the term we execute and is used to generate the program's man
page. Since we provided a [~version] string, the program will
automatically respond to the [--version] option by printing this
string.

A program using {!Term.eval} always responds to the [--help] option by
showing the man page about the program generated using the information
you provided with {!Term.info} and {!Arg.info}.  Here is the output
generated by our example :

{v
> ./chorus --help
NAME
       chorus - print a customizable message repeatedly

SYNOPSIS
       chorus [OPTION]... [MSG]

ARGUMENTS
       MSG (absent=Revolt! or CHORUS_MSG env)
           The message to print.

OPTIONS
       -c COUNT, --count=COUNT (absent=10)
           Repeat the message COUNT times.

       --help[=FMT] (default=auto)
           Show this help in format FMT. The value FMT must be one of `auto',
           `pager', `groff' or `plain'. With `auto', the format is `pager` or
           `plain' whenever the TERM env var is `dumb' or undefined.

       --version
           Show version information.

EXIT STATUS
       chorus exits with the following status:

       0   on success.

       124 on command line parsing errors.

       125 on unexpected internal errors (bugs).

ENVIRONMENT
       These environment variables affect the execution of chorus:

       CHORUS_MSG
           Overrides the default message to print.

BUGS
       Email bug reports to <hehey at example.org>.
v}

If a pager is available, this output is written to a pager. This help
is also available in plain text or in the
{{:http://www.gnu.org/software/groff/groff.html}groff} man page format
by invoking the program with the option [--help=plain] or
[--help=groff].

For examples of more complex command line definitions look and run
the {{!examples}examples}.

{2:multiterms Multiple terms}

[Esy_cmdliner] also provides support for programs like [darcs] or [git]
that have multiple commands each with their own syntax:

{[prog COMMAND [OPTION]... ARG...]}

A command is defined by coupling a term with {{!Term.tinfo}term
information}. The term information defines the command name and its
man page. Given a list of commands the function {!Term.eval_choice}
will execute the term corresponding to the [COMMAND] argument or a
specific "main" term if there is no [COMMAND] argument.

{2:doclang Documentation markup language}

Manpage {{!Manpage.block}blocks} and doc strings support the following
markup language.

{ul
{- Markup directives [$(i,text)] and [$(b,text)], where [text] is raw
   text respectively rendered in italics and bold.}
{- Outside markup directives, context dependent variables of the form
   [$(var)] are substituted by marked up data. For example in a term's
   man page [$(tname)] is substituted by the term name in bold.}
{- Characters $, (, ) and \ can respectively be escaped by \$, \(, \)
   and \\ (in OCaml strings this will be ["\\$"], ["\\("], ["\\)"],
   ["\\\\"]). Escaping $ and \ is mandatory everywhere. Escaping ) is
   mandatory only in markup directives. Escaping ( is only here for
   your symmetric pleasure. Any other sequence of characters starting
   with a \ is an illegal character sequence.}
{- Refering to unknown markup directives or variables will generate
   errors on standard error during documentation generation.}}

{2:manual Manual}

Man page sections for a term are printed in the order specified by the
term manual as given to {!Term.info}. Unless specified explicitely in
the term's manual the following sections are automaticaly created and
populated for you:

{ul
{- {{!Manpage.s_name}[NAME]} section.}
{- {{!Manpage.s_synopsis}[SYNOPSIS]} section.}}

The various [doc] documentation strings specified by the term's
subterms and additional metadata get inserted at the end of the
documentation section name [docs] they respectively mention, in the
following order:

{ol
{- Commands, see {!Term.info}.}
{- Positional arguments, see {!Arg.info}. Those are listed iff
   both the [docv] and [doc] string is specified by {!Arg.info}.}
{- Optional arguments, see {!Arg.info}.}
{- Exit statuses, see {!Term.exit_info}.}
{- Environment variables, see {!Arg.env_var} and {!Term.env_info}.}}

If a [docs] section name is mentioned and does not exist in the term's
manual, an empty section is created for it, after which the [doc] strings
are inserted, possibly prefixed by boilerplate text (e.g. for
{!Manpage.s_environment} and {!Manpage.s_exit_status}).

If the created section is:
{ul
{- {{!Manpage.standard_sections}standard}, it
    is inserted at the right place in the order specified
    {{!Manpage.standard_sections}here}, but after a possible non-standard
    section explicitely specified by the term since the latter get the
    order number of the last previously specified standard section
    or the order of {!Manpage.s_synopsis} if there is no such section.}
{-  non-standard, it is inserted before the {!Manpage.s_commands}
    section or the first subsequent existing standard section if it
    doesn't exist. Taking advantage of this behaviour is discouraged,
    you should declare manually your non standard section in the term's
    manual.}}

Ideally all manual strings should be UTF-8 encoded. However at the
moment macOS (until at least 10.12) is stuck with [groff 1.19.2] which
doesn't support `preconv(1)`. Regarding UTF-8 output, generating the
man page with [-Tutf8] maps the hyphen-minus [U+002D] to the minus
sign [U+2212] which makes it difficult to search it in the pager, so
[-Tascii] is used for now.  Conclusion is that it is better to stick
to the ASCII set for now. Please contact the author if something seems
wrong in this reasoning or if you know a work around this.

{2:misc Miscellaneous}

{ul
{- The option name [--cmdliner] is reserved by the library.}
{- The option name [--help], (and [--version] if you specify a version
   string) is reserved by the library. Using it as a term or option
   name may result in undefined behaviour.}
{- Defining the same option or command name via two different
   arguments or terms is illegal and raises [Invalid_argument].}}

{1:cmdline Command line syntax}

For programs evaluating a single term the most general form of invocation is:

{[
prog [OPTION]... [ARG]...
]}

The program automatically reponds to the [--help] option by printing
the help. If a version string is provided in the {{!Term.tinfo}term
information}, it also automatically responds to the [--version] option
by printing this string.

Command line arguments are either {{!optargs}{e optional}} or
{{!posargs}{e positional}}. Both can be freely interleaved but since
[Esy_cmdliner] accepts many optional forms this may result in
ambiguities. The special {{!posargs} token [--]} can be used to
resolve them.

Programs evaluating multiple terms also add this form of invocation:

{[
prog COMMAND [OPTION]... [ARG]...
]}

Commands automatically respond to the [--help] option by printing
their help. The [COMMAND] string must be the first string following
the program name and may be specified by a prefix as long as it is not
ambiguous.

{2:optargs Optional arguments}

An optional argument is specified on the command line by a {e name}
possibly followed by a {e value}.

The name of an option can be short or long.

{ul
{- A {e short} name is a dash followed by a single alphanumeric
   character: ["-h"], ["-q"], ["-I"].}
{- A {e long} name is two dashes followed by alphanumeric
   characters and dashes: ["--help"], ["--silent"], ["--ignore-case"].}}

More than one name may refer to the same optional argument.  For
example in a given program the names ["-q"], ["--quiet"] and
["--silent"] may all stand for the same boolean argument indicating
the program to be quiet.  Long names can be specified by any non
ambiguous prefix.

The value of an option can be specified in three different ways.

{ul
{- As the next token on the command line: ["-o a.out"], ["--output a.out"].}
{- Glued to a short name: ["-oa.out"].}
{- Glued to a long name after an equal character: ["--output=a.out"].}}

Glued forms are especially useful if the value itself starts with a
dash as is the case for negative numbers, ["--min=-10"].

An optional argument without a value is either a {e flag} (see
{!Arg.flag}, {!Arg.vflag}) or an optional argument with an optional
value (see the [~vopt] argument of {!Arg.opt}).

Short flags can be grouped together to share a single dash and the
group can end with a short option. For example assuming ["-v"] and
["-x"] are flags and ["-f"] is a short option:

{ul
{- ["-vx"] will be parsed as ["-v -x"].}
{- ["-vxfopt"] will be parsed as ["-v -x -fopt"].}
{- ["-vxf opt"] will be parsed as ["-v -x -fopt"].}
{- ["-fvx"] will be parsed as ["-f=vx"].}}

{2:posargs Positional arguments}

Positional arguments are tokens on the command line that are not
option names and are not the value of an optional argument. They are
numbered from left to right starting with zero.

Since positional arguments may be mistaken as the optional value of an
optional argument or they may need to look like option names, anything
that follows the special token ["--"] on the command line is
considered to be a positional argument.

{2:envlookup Environment variables}

Non-required command line arguments can be backed up by an environment
variable.  If the argument is absent from the command line and that
the environment variable is defined, its value is parsed using the
argument converter and defines the value of the argument.

For {!Arg.flag} and {!Arg.flag_all} that do not have an argument converter a
boolean is parsed from the lowercased variable value as follows:


{ul
{- [""], ["false"], ["no"], ["n"] or ["0"] is [false].}
{- ["true"], ["yes"], ["y"] or ["1"] is [true].}
{- Any other string is an error.}}

Note that environment variables are not supported for {!Arg.vflag} and
{!Arg.vflag_all}.

{1:examples Examples}

These examples are in the [test] directory of the distribution.

{2:exrm A [rm] command}

We define the command line interface of a [rm] command with the synopsis:

{[
rm [OPTION]... FILE...
]}

The [-f], [-i] and [-I] flags define the prompt behaviour of [rm],
represented in our program by the [prompt] type. If more than one of
these flags is present on the command line the last one takes
precedence.

To implement this behaviour we map the presence of these flags to
values of the [prompt] type by using {!Arg.vflag_all}.  This argument
will contain all occurrences of the flag on the command line and we
just take the {!Arg.last} one to define our term value (if there's no
occurrence the last value of the default list [[Always]] is taken,
i.e. the default is [Always]).

{[
(* Implementation of the command, we just print the args. *)

type prompt = Always | Once | Never
let prompt_str = function
| Always -> "always" | Once -> "once" | Never -> "never"

let rm prompt recurse files =
  Printf.printf "prompt = %s\nrecurse = %B\nfiles = %s\n"
    (prompt_str prompt) recurse (String.concat ", " files)

(* Command line interface *)

open Esy_cmdliner

let files = Arg.(non_empty & pos_all file [] & info [] ~docv:"FILE")
let prompt =
  let doc = "Prompt before every removal." in
  let always = Always, Arg.info ["i"] ~doc in
  let doc = "Ignore nonexistent files and never prompt." in
  let never = Never, Arg.info ["f"; "force"] ~doc in
  let doc = "Prompt once before removing more than three files, or when
             removing recursively. Less intrusive than $(b,-i), while
             still giving protection against most mistakes."
  in
  let once = Once, Arg.info ["I"] ~doc in
  Arg.(last & vflag_all [Always] [always; never; once])

let recursive =
  let doc = "Remove directories and their contents recursively." in
  Arg.(value & flag & info ["r"; "R"; "recursive"] ~doc)

let cmd =
  let doc = "remove files or directories" in
  let man = [
    `S Manpage.s_description;
    `P "$(tname) removes each specified $(i,FILE). By default it does not
        remove directories, to also remove them and their contents, use the
        option $(b,--recursive) ($(b,-r) or $(b,-R)).";
    `P "To remove a file whose name starts with a `-', for example
        `-foo', use one of these commands:";
    `P "rm -- -foo"; `Noblank;
    `P "rm ./-foo";
    `P "$(tname) removes symbolic links, not the files referenced by the
        links.";
    `S Manpage.s_bugs; `P "Report bugs to <hehey at example.org>.";
    `S Manpage.s_see_also; `P "$(b,rmdir)(1), $(b,unlink)(2)" ]
  in
  Term.(const rm $ prompt $ recursive $ files),
  Term.info "rm" ~version:"%%VERSION%%" ~doc ~exits:Term.default_exits ~man

let () = Term.(exit @@ eval cmd)
]}

{2:excp A [cp] command}

We define the command line interface of a [cp] command with the synopsis:
{[
cp [OPTION]... SOURCE... DEST
]}

The [DEST] argument must be a directory if there is more than one
[SOURCE]. This constraint is too complex to be expressed by the
combinators of {!Arg}. Hence we just give it the {!Arg.string} type
and verify the constraint at the beginning of the [cp]
implementation. If unsatisfied we return an [`Error] and by using
{!Term.ret} on the lifted result [cp_t] of [cp], [Esy_cmdliner] handles
the error reporting.

{[
(* Implementation, we check the dest argument and print the args *)

let cp verbose recurse force srcs dest =
  if List.length srcs > 1 &&
  (not (Sys.file_exists dest) || not (Sys.is_directory dest))
  then
    `Error (false, dest ^ " is not a directory")
  else
    `Ok (Printf.printf
     "verbose = %B\nrecurse = %B\nforce = %B\nsrcs = %s\ndest = %s\n"
      verbose recurse force (String.concat ", " srcs) dest)

(* Command line interface *)

open Esy_cmdliner

let verbose =
  let doc = "Print file names as they are copied." in
  Arg.(value & flag & info ["v"; "verbose"] ~doc)

let recurse =
  let doc = "Copy directories recursively." in
  Arg.(value & flag & info ["r"; "R"; "recursive"] ~doc)

let force =
  let doc = "If a destination file cannot be opened, remove it and try again."in
  Arg.(value & flag & info ["f"; "force"] ~doc)

let srcs =
  let doc = "Source file(s) to copy." in
  Arg.(non_empty & pos_left ~rev:true 0 file [] & info [] ~docv:"SOURCE" ~doc)

let dest =
  let doc = "Destination of the copy. Must be a directory if there is more
             than one $(i,SOURCE)." in
  Arg.(required & pos ~rev:true 0 (some string) None & info [] ~docv:"DEST"
         ~doc)

let cmd =
  let doc = "copy files" in
  let man_xrefs =
    [ `Tool "mv"; `Tool "scp"; `Page (2, "umask"); `Page (7, "symlink") ]
  in
  let exits = Term.default_exits in
  let man =
    [ `S Manpage.s_bugs;
      `P "Email them to <hehey at example.org>."; ]
  in
  Term.(ret (const cp $ verbose $ recurse $ force $ srcs $ dest)),
  Term.info "cp" ~version:"%%VERSION%%" ~doc ~exits ~man ~man_xrefs

let () = Term.(exit @@ eval cmd)
]}

{2:extail A [tail] command}

We define the command line interface of a [tail] command with the
synopsis:

{[
tail [OPTION]... [FILE]...
]}

The [--lines] option whose value specifies the number of last lines to
print has a special syntax where a [+] prefix indicates to start
printing from that line number. In the program this is represented by
the [loc] type. We define a custom [loc] {{!Arg.argconv}argument
converter} for this option.

The [--follow] option has an optional enumerated value. The argument
converter [follow], created with {!Arg.enum} parses the option value
into the enumeration. By using {!Arg.some} and the [~vopt] argument of
{!Arg.opt}, the term corresponding to the option [--follow] evaluates
to [None] if [--follow] is absent from the command line, to [Some
Descriptor] if present but without a value and to [Some v] if present
with a value [v] specified.

{[
(* Implementation of the command, we just print the args. *)

type loc = bool * int
type verb = Verbose | Quiet
type follow = Name | Descriptor

let str = Printf.sprintf
let opt_str sv = function None -> "None" | Some v -> str "Some(%s)" (sv v)
let loc_str (rev, k) = if rev then str "%d" k else str "+%d" k
let follow_str = function Name -> "name" | Descriptor -> "descriptor"
let verb_str = function Verbose -> "verbose" | Quiet -> "quiet"

let tail lines follow verb pid files =
  Printf.printf "lines = %s\nfollow = %s\nverb = %s\npid = %s\nfiles = %s\n"
    (loc_str lines) (opt_str follow_str follow) (verb_str verb)
    (opt_str string_of_int pid) (String.concat ", " files)

(* Command line interface *)

open Esy_cmdliner

let lines =
  let loc =
    let parse s =
      try
        if s <> "" && s.[0] <> '+' then Ok (true, int_of_string s) else
        Ok (false, int_of_string (String.sub s 1 (String.length s - 1)))
      with Failure _ -> Error (`Msg "unable to parse integer")
    in
    let print ppf p = Format.fprintf ppf "%s" (loc_str p) in
    Arg.conv ~docv:"N" (parse, print)
  in
  Arg.(value & opt loc (true, 10) & info ["n"; "lines"] ~docv:"N"
         ~doc:"Output the last $(docv) lines or use $(i,+)$(docv) to start
               output after the $(i,N)-1th line.")

let follow =
  let doc = "Output appended data as the file grows. $(docv) specifies how the
             file should be tracked, by its `name' or by its `descriptor'." in
  let follow = Arg.enum ["name", Name; "descriptor", Descriptor] in
  Arg.(value & opt (some follow) ~vopt:(Some Descriptor) None &
       info ["f"; "follow"] ~docv:"ID" ~doc)

let verb =
  let doc = "Never output headers giving file names." in
  let quiet = Quiet, Arg.info ["q"; "quiet"; "silent"] ~doc in
  let doc = "Always output headers giving file names." in
  let verbose = Verbose, Arg.info ["v"; "verbose"] ~doc in
  Arg.(last & vflag_all [Quiet] [quiet; verbose])

let pid =
  let doc = "With -f, terminate after process $(docv) dies." in
  Arg.(value & opt (some int) None & info ["pid"] ~docv:"PID" ~doc)

let files = Arg.(value & (pos_all non_dir_file []) & info [] ~docv:"FILE")

let cmd =
  let doc = "display the last part of a file" in
  let man = [
    `S Manpage.s_description;
    `P "$(tname) prints the last lines of each $(i,FILE) to standard output. If
        no file is specified reads standard input. The number of printed
        lines can be  specified with the $(b,-n) option.";
    `S Manpage.s_bugs;
    `P "Report them to <hehey at example.org>.";
    `S Manpage.s_see_also;
    `P "$(b,cat)(1), $(b,head)(1)" ]
  in
  Term.(const tail $ lines $ follow $ verb $ pid $ files),
  Term.info "tail" ~version:"%‌%VERSION%%" ~doc ~exits:Term.default_exits ~man

let () = Term.(exit @@ eval cmd)
]}

{2:exdarcs A [darcs] command}

We define the command line interface of a [darcs] command with the
synopsis:

{[
darcs [COMMAND] ...
]}

The [--debug], [-q], [-v] and [--prehook] options are available in
each command.  To avoid having to pass them individually to each
command we gather them in a record of type [copts]. By lifting the
record constructor [copts] into the term [copts_t] we now have a term
that we can pass to the commands to stand for an argument of type
[copts]. These options are documented in a section called [COMMON
OPTIONS], since we also want to put [--help] and [--version] in this
section, the term information of commands makes a judicious use of the
[sdocs] parameter of {!Term.info}.

The [help] command shows help about commands or other topics. The help
shown for commands is generated by [Esy_cmdliner] by making an appropriate
use of {!Term.ret} on the lifted [help] function.

If the program is invoked without a command we just want to show the
help of the program as printed by [Esy_cmdliner] with [--help]. This is
done by the [default_cmd] term.

{[
(* Implementations, just print the args. *)

type verb = Normal | Quiet | Verbose
type copts = { debug : bool; verb : verb; prehook : string option }

let str = Printf.sprintf
let opt_str sv = function None -> "None" | Some v -> str "Some(%s)" (sv v)
let opt_str_str = opt_str (fun s -> s)
let verb_str = function
  | Normal -> "normal" | Quiet -> "quiet" | Verbose -> "verbose"

let pr_copts oc copts = Printf.fprintf oc
    "debug = %B\nverbosity = %s\nprehook = %s\n"
    copts.debug (verb_str copts.verb) (opt_str_str copts.prehook)

let initialize copts repodir = Printf.printf
    "%arepodir = %s\n" pr_copts copts repodir

let record copts name email all ask_deps files = Printf.printf
    "%aname = %s\nemail = %s\nall = %B\nask-deps = %B\nfiles = %s\n"
    pr_copts copts (opt_str_str name) (opt_str_str email) all ask_deps
    (String.concat ", " files)

let help copts man_format cmds topic = match topic with
| None -> `Help (`Pager, None) (* help about the program. *)
| Some topic ->
    let topics = "topics" :: "patterns" :: "environment" :: cmds in
    let conv, _ = Esy_cmdliner.Arg.enum (List.rev_map (fun s -> (s, s)) topics) in
    match conv topic with
    | `Error e -> `Error (false, e)
    | `Ok t when t = "topics" -> List.iter print_endline topics; `Ok ()
    | `Ok t when List.mem t cmds -> `Help (man_format, Some t)
    | `Ok t ->
        let page = (topic, 7, "", "", ""), [`S topic; `P "Say something";] in
        `Ok (Esy_cmdliner.Manpage.print man_format Format.std_formatter page)

open Esy_cmdliner

(* Help sections common to all commands *)

let help_secs = [
 `S Manpage.s_common_options;
 `P "These options are common to all commands.";
 `S "MORE HELP";
 `P "Use `$(mname) $(i,COMMAND) --help' for help on a single command.";`Noblank;
 `P "Use `$(mname) help patterns' for help on patch matching."; `Noblank;
 `P "Use `$(mname) help environment' for help on environment variables.";
 `S Manpage.s_bugs; `P "Check bug reports at http://bugs.example.org.";]

(* Options common to all commands *)

let copts debug verb prehook = { debug; verb; prehook }
let copts_t =
  let docs = Manpage.s_common_options in
  let debug =
    let doc = "Give only debug output." in
    Arg.(value & flag & info ["debug"] ~docs ~doc)
  in
  let verb =
    let doc = "Suppress informational output." in
    let quiet = Quiet, Arg.info ["q"; "quiet"] ~docs ~doc in
    let doc = "Give verbose output." in
    let verbose = Verbose, Arg.info ["v"; "verbose"] ~docs ~doc in
    Arg.(last & vflag_all [Normal] [quiet; verbose])
  in
  let prehook =
    let doc = "Specify command to run before this $(mname) command." in
    Arg.(value & opt (some string) None & info ["prehook"] ~docs ~doc)
  in
  Term.(const copts $ debug $ verb $ prehook)

(* Commands *)

let initialize_cmd =
  let repodir =
    let doc = "Run the program in repository directory $(docv)." in
    Arg.(value & opt file Filename.current_dir_name & info ["repodir"]
           ~docv:"DIR" ~doc)
  in
  let doc = "make the current directory a repository" in
  let exits = Term.default_exits in
  let man = [
    `S Manpage.s_description;
    `P "Turns the current directory into a Darcs repository. Any
       existing files and subdirectories become ...";
    `Blocks help_secs; ]
  in
  Term.(const initialize $ copts_t $ repodir),
  Term.info "initialize" ~doc ~sdocs:Manpage.s_common_options ~exits ~man

let record_cmd =
  let pname =
    let doc = "Name of the patch." in
    Arg.(value & opt (some string) None & info ["m"; "patch-name"] ~docv:"NAME"
           ~doc)
  in
  let author =
    let doc = "Specifies the author's identity." in
    Arg.(value & opt (some string) None & info ["A"; "author"] ~docv:"EMAIL"
           ~doc)
  in
  let all =
    let doc = "Answer yes to all patches." in
    Arg.(value & flag & info ["a"; "all"] ~doc)
  in
  let ask_deps =
    let doc = "Ask for extra dependencies." in
    Arg.(value & flag & info ["ask-deps"] ~doc)
  in
  let files = Arg.(value & (pos_all file) [] & info [] ~docv:"FILE or DIR") in
  let doc = "create a patch from unrecorded changes" in
  let exits = Term.default_exits in
  let man =
    [`S Manpage.s_description;
     `P "Creates a patch from changes in the working tree. If you specify
         a set of files ...";
     `Blocks help_secs; ]
  in
  Term.(const record $ copts_t $ pname $ author $ all $ ask_deps $ files),
  Term.info "record" ~doc ~sdocs:Manpage.s_common_options ~exits ~man

let help_cmd =
  let topic =
    let doc = "The topic to get help on. `topics' lists the topics." in
    Arg.(value & pos 0 (some string) None & info [] ~docv:"TOPIC" ~doc)
  in
  let doc = "display help about darcs and darcs commands" in
  let man =
    [`S Manpage.s_description;
     `P "Prints help about darcs commands and other subjects...";
     `Blocks help_secs; ]
  in
  Term.(ret
          (const help $ copts_t $ Arg.man_format $ Term.choice_names $topic)),
  Term.info "help" ~doc ~exits:Term.default_exits ~man

let default_cmd =
  let doc = "a revision control system" in
  let sdocs = Manpage.s_common_options in
  let exits = Term.default_exits in
  let man = help_secs in
  Term.(ret (const (fun _ -> `Help (`Pager, None)) $ copts_t)),
  Term.info "darcs" ~version:"%%VERSION%%" ~doc ~sdocs ~exits ~man

let cmds = [initialize_cmd; record_cmd; help_cmd]

let () = Term.(exit @@ eval_choice default_cmd cmds)
]}
*)

(*---------------------------------------------------------------------------
   Copyright (c) 2011 Daniel C. Bünzli

   Permission to use, copy, modify, and/or distribute this software for any
   purpose with or without fee is hereby granted, provided that the above
   copyright notice and this permission notice appear in all copies.


   THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
   WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
   MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
   ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
   WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
   ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
   OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
  ---------------------------------------------------------------------------*)
