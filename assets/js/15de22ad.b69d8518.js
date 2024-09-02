"use strict";(self.webpackChunksite_v_3=self.webpackChunksite_v_3||[]).push([[8178],{2969:(e,n,s)=>{s.r(n),s.d(n,{assets:()=>r,contentTitle:()=>l,default:()=>h,frontMatter:()=>d,metadata:()=>o,toc:()=>a});var i=s(5893),c=s(1151);const d={id:"low-level-commands",title:"Low Level Commands"},l=void 0,o={id:"low-level-commands",title:"Low Level Commands",description:"esy provides a set of low level commands which enable more configurable",source:"@site/../docs/low-level-commands.md",sourceDirName:".",slug:"/low-level-commands",permalink:"/docs/low-level-commands",draft:!1,unlisted:!1,editUrl:"https://github.com/esy/esy/tree/master/docs/../docs/low-level-commands.md",tags:[],version:"current",lastUpdatedBy:"prometheansacrifice",lastUpdatedAt:1725276666,formattedLastUpdatedAt:"Sep 2, 2024",frontMatter:{id:"low-level-commands",title:"Low Level Commands"},sidebar:"docs",previous:{title:"Commands",permalink:"/docs/commands"},next:{title:"Configuration",permalink:"/docs/esy-configuration"}},r={},a=[{value:"Managing installations",id:"managing-installations",level:2},{value:"<code>esy solve</code>",id:"esy-solve",level:3},{value:"<code>esy fetch</code>",id:"esy-fetch",level:3},{value:"Managing build environment",id:"managing-build-environment",level:2},{value:"<code>esy build-dependencies</code>",id:"esy-build-dependencies",level:3},{value:"<code>esy command-exec</code>",id:"esy-command-exec",level:3},{value:"<code>esy print-env</code>",id:"esy-print-env",level:3},{value:"DEPSPEC",id:"depspec",level:2}];function t(e){const n={code:"code",h2:"h2",h3:"h3",li:"li",p:"p",pre:"pre",ul:"ul",...(0,c.a)(),...e.components};return(0,i.jsxs)(i.Fragment,{children:[(0,i.jsx)(n.p,{children:"esy provides a set of low level commands which enable more configurable\nworkflows."}),"\n",(0,i.jsx)(n.p,{children:"Such commands are grouped into two concerns:"}),"\n",(0,i.jsxs)(n.ul,{children:["\n",(0,i.jsx)(n.li,{children:"Managing installations"}),"\n",(0,i.jsx)(n.li,{children:"Managing build environments"}),"\n"]}),"\n",(0,i.jsx)(n.h2,{id:"managing-installations",children:"Managing installations"}),"\n",(0,i.jsx)(n.p,{children:"The following commands helps managing installations of dependencies."}),"\n",(0,i.jsxs)(n.p,{children:["The end product of an installation procedure is a solution lock (",(0,i.jsx)(n.code,{children:"esy.lock"}),"\ndirectory) which describes the package graph which corresponds to the\nconstraints defined in ",(0,i.jsx)(n.code,{children:"package.json"})," manifest."]}),"\n",(0,i.jsxs)(n.p,{children:["User typically don't need to run those commands but rather use ",(0,i.jsx)(n.code,{children:"esy install"}),"\ninvocation or ",(0,i.jsx)(n.code,{children:"esy"})," invocation which performs installation procedure as needed."]}),"\n",(0,i.jsx)(n.h3,{id:"esy-solve",children:(0,i.jsx)(n.code,{children:"esy solve"})}),"\n",(0,i.jsxs)(n.p,{children:[(0,i.jsx)(n.code,{children:"esy solve"})," command performs dependency resolution and produces the solution lock\n(",(0,i.jsx)(n.code,{children:"esy.lock"})," directory). It doesn't fetch package sources."]}),"\n",(0,i.jsx)(n.h3,{id:"esy-fetch",children:(0,i.jsx)(n.code,{children:"esy fetch"})}),"\n",(0,i.jsxs)(n.p,{children:[(0,i.jsx)(n.code,{children:"esy fetch"})," command fetches package sources as defined in ",(0,i.jsx)(n.code,{children:"esy.lock"})," making\npackage sources available for the next commands in the pipeline."]}),"\n",(0,i.jsx)(n.h2,{id:"managing-build-environment",children:"Managing build environment"}),"\n",(0,i.jsxs)(n.p,{children:["The following commands operate on a project which has the ",(0,i.jsx)(n.code,{children:"esy.lock"})," produced\nand sources fetched."]}),"\n",(0,i.jsx)(n.h3,{id:"esy-build-dependencies",children:(0,i.jsx)(n.code,{children:"esy build-dependencies"})}),"\n",(0,i.jsxs)(n.p,{children:[(0,i.jsx)(n.code,{children:"esy build-dependencies"})," command builds dependencies in a given build\nenvironment for a given package:"]}),"\n",(0,i.jsx)(n.pre,{children:(0,i.jsx)(n.code,{className:"language-bash",children:"esy build-dependencies [OPTION]... [PACKAGE]\n"})}),"\n",(0,i.jsxs)(n.p,{children:["Note that by default only regular packages are built, to build linked packages\none need to pass ",(0,i.jsx)(n.code,{children:"--all"})," command line flag."]}),"\n",(0,i.jsx)(n.p,{children:"Arguments:"}),"\n",(0,i.jsxs)(n.ul,{children:["\n",(0,i.jsxs)(n.li,{children:[(0,i.jsx)(n.code,{children:"PACKAGE"})," (optional, default: ",(0,i.jsx)(n.code,{children:"root"}),") Package to build dependencies for."]}),"\n"]}),"\n",(0,i.jsx)(n.p,{children:"Options:"}),"\n",(0,i.jsxs)(n.ul,{children:["\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsxs)(n.p,{children:[(0,i.jsx)(n.code,{children:"--all"})," Build all dependencies (including linked packages)"]}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsxs)(n.p,{children:[(0,i.jsx)(n.code,{children:"--release"}),' Force to use "esy.build" commands (by default "esy.buildDev"\ncommands are used)']}),"\n",(0,i.jsxs)(n.p,{children:["By default linked packages are built using ",(0,i.jsx)(n.code,{children:'"esy.buildDev"'})," commands defined\nin their corresponding ",(0,i.jsx)(n.code,{children:"package.json"})," manifests, passing ",(0,i.jsx)(n.code,{children:"--release"})," makes\nbuild process use ",(0,i.jsx)(n.code,{children:'"esy.build"'})," commands instead."]}),"\n"]}),"\n"]}),"\n",(0,i.jsx)(n.h3,{id:"esy-command-exec",children:(0,i.jsx)(n.code,{children:"esy command-exec"})}),"\n",(0,i.jsxs)(n.p,{children:[(0,i.jsx)(n.code,{children:"esy-exec-command"})," command executes a command in a given environment:"]}),"\n",(0,i.jsx)(n.pre,{children:(0,i.jsx)(n.code,{className:"language-bash",children:"esy exec-command [OPTION]... PACKAGE COMMAND...\n"})}),"\n",(0,i.jsx)(n.p,{children:"Arguments:"}),"\n",(0,i.jsxs)(n.ul,{children:["\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsxs)(n.p,{children:[(0,i.jsx)(n.code,{children:"COMMAND"})," (required) Command to execute within the environment."]}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsxs)(n.p,{children:[(0,i.jsx)(n.code,{children:"PACKAGE"})," (required) Package in which environment execute the command."]}),"\n"]}),"\n"]}),"\n",(0,i.jsx)(n.p,{children:"Options:"}),"\n",(0,i.jsxs)(n.ul,{children:["\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsxs)(n.p,{children:[(0,i.jsx)(n.code,{children:"--build-context"})," Initialize package's build context before executing the command."]}),"\n",(0,i.jsx)(n.p,{children:"This provides the identical context as when running package build commands."}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsxs)(n.p,{children:[(0,i.jsx)(n.code,{children:"--envspec=DEPSPEC"})," Define DEPSPEC expression which is used to construct the\nenvironment for the command invocation."]}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsxs)(n.p,{children:[(0,i.jsx)(n.code,{children:"--include-build-env"})," Include build environment."]}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsxs)(n.p,{children:[(0,i.jsx)(n.code,{children:"--include-current-env"})," Include current environment."]}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsxs)(n.p,{children:[(0,i.jsx)(n.code,{children:"--include-npm-bin"})," Include npm bin in ",(0,i.jsx)(n.code,{children:"$PATH"}),"."]}),"\n"]}),"\n"]}),"\n",(0,i.jsx)(n.h3,{id:"esy-print-env",children:(0,i.jsx)(n.code,{children:"esy print-env"})}),"\n",(0,i.jsxs)(n.p,{children:[(0,i.jsx)(n.code,{children:"esy-print-env"})," command prints a configured environment on stdout:"]}),"\n",(0,i.jsx)(n.pre,{children:(0,i.jsx)(n.code,{className:"language-bash",children:"esy print-env [OPTION]... PACKAGE\n"})}),"\n",(0,i.jsx)(n.p,{children:"Arguments:"}),"\n",(0,i.jsxs)(n.ul,{children:["\n",(0,i.jsxs)(n.li,{children:[(0,i.jsx)(n.code,{children:"PACKAGE"})," (required) Package in which environment execute the command."]}),"\n"]}),"\n",(0,i.jsx)(n.p,{children:"Options:"}),"\n",(0,i.jsxs)(n.ul,{children:["\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsxs)(n.p,{children:[(0,i.jsx)(n.code,{children:"--envspec=DEPSPEC"})," Define DEPSPEC expression which is used to construct the\nenvironment for the command invocation."]}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsxs)(n.p,{children:[(0,i.jsx)(n.code,{children:"--include-build-env"})," Include build environment. This includes some special\n",(0,i.jsx)(n.code,{children:"$cur__*"})," envirironment variables, as well as environment variables configured\nin the ",(0,i.jsx)(n.code,{children:"esy.buildEnv"})," section of the package config."]}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsxs)(n.p,{children:[(0,i.jsx)(n.code,{children:"--include-current-env"})," Include current environment."]}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsxs)(n.p,{children:[(0,i.jsx)(n.code,{children:"--include-npm-bin"})," Include npm bin in ",(0,i.jsx)(n.code,{children:"$PATH"}),"."]}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsxs)(n.p,{children:[(0,i.jsx)(n.code,{children:"--json"})," Format output as JSON"]}),"\n"]}),"\n"]}),"\n",(0,i.jsx)(n.h2,{id:"depspec",children:"DEPSPEC"}),"\n",(0,i.jsxs)(n.p,{children:["Some commands allow to define how an environment is constructed for each package\nbased on other packages in a dependency graph (see ",(0,i.jsx)(n.code,{children:"--envspec"})," command option\ndescribed above). This is done via DEPSPEC expressions."]}),"\n",(0,i.jsx)(n.p,{children:"There are the following constructs available in DEPSPEC:"}),"\n",(0,i.jsxs)(n.ul,{children:["\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsxs)(n.p,{children:[(0,i.jsx)(n.code,{children:"self"})," refers to the current package, for which the environment is being constructed."]}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsxs)(n.p,{children:[(0,i.jsx)(n.code,{children:"root"})," refers to the root package in an esy project."]}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsxs)(n.p,{children:[(0,i.jsx)(n.code,{children:"dependencies(PKG)"})," refers to a set of ",(0,i.jsx)(n.code,{children:'"dependencies"'})," of ",(0,i.jsx)(n.code,{children:"PKG"})," package."]}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsxs)(n.p,{children:[(0,i.jsx)(n.code,{children:"devDependencies(PKG)"})," refers to a set of ",(0,i.jsx)(n.code,{children:'"devDependencies"'})," of ",(0,i.jsx)(n.code,{children:"PKG"})," package."]}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsxs)(n.p,{children:[(0,i.jsx)(n.code,{children:"EXPR1 + EXPR2"})," refers to a set of packages found in ",(0,i.jsx)(n.code,{children:"EXPR1"})," or ",(0,i.jsx)(n.code,{children:"EXPR2"}),"\n(union)."]}),"\n"]}),"\n"]}),"\n",(0,i.jsx)(n.p,{children:"Examples:"}),"\n",(0,i.jsxs)(n.ul,{children:["\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsx)(n.p,{children:"Dependencies of the current package:"}),"\n",(0,i.jsx)(n.pre,{children:(0,i.jsx)(n.code,{className:"language-bash",children:"dependencies(self)\n"})}),"\n",(0,i.jsx)(n.p,{children:"This constructs the environment which is analogous to the environment used to\nbuild packages."}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsx)(n.p,{children:"Dev dependencies of the root package:"}),"\n",(0,i.jsx)(n.pre,{children:(0,i.jsx)(n.code,{className:"language-bash",children:"devDependencies(root)\n"})}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsx)(n.p,{children:"Dependencies of the current package and the package itself:"}),"\n",(0,i.jsx)(n.pre,{children:(0,i.jsx)(n.code,{className:"language-bash",children:"dependencies(self) + self\n"})}),"\n",(0,i.jsxs)(n.p,{children:["This constructs the environment which is analogous to the environment used in\n",(0,i.jsx)(n.code,{children:"esy x CMD"})," invocations."]}),"\n"]}),"\n"]})]})}function h(e={}){const{wrapper:n}={...(0,c.a)(),...e.components};return n?(0,i.jsx)(n,{...e,children:(0,i.jsx)(t,{...e})}):t(e)}},1151:(e,n,s)=>{s.d(n,{Z:()=>o,a:()=>l});var i=s(7294);const c={},d=i.createContext(c);function l(e){const n=i.useContext(d);return i.useMemo((function(){return"function"==typeof e?e(n):{...n,...e}}),[n,e])}function o(e){let n;return n=e.disableParentContext?"function"==typeof e.components?e.components(c):e.components||c:l(e.components),i.createElement(d.Provider,{value:n},e.children)}}}]);