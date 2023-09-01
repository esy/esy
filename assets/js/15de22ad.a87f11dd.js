"use strict";(self.webpackChunksite_v_3=self.webpackChunksite_v_3||[]).push([[8178],{3905:(e,n,t)=>{t.d(n,{Zo:()=>d,kt:()=>k});var a=t(7294);function i(e,n,t){return n in e?Object.defineProperty(e,n,{value:t,enumerable:!0,configurable:!0,writable:!0}):e[n]=t,e}function l(e,n){var t=Object.keys(e);if(Object.getOwnPropertySymbols){var a=Object.getOwnPropertySymbols(e);n&&(a=a.filter((function(n){return Object.getOwnPropertyDescriptor(e,n).enumerable}))),t.push.apply(t,a)}return t}function r(e){for(var n=1;n<arguments.length;n++){var t=null!=arguments[n]?arguments[n]:{};n%2?l(Object(t),!0).forEach((function(n){i(e,n,t[n])})):Object.getOwnPropertyDescriptors?Object.defineProperties(e,Object.getOwnPropertyDescriptors(t)):l(Object(t)).forEach((function(n){Object.defineProperty(e,n,Object.getOwnPropertyDescriptor(t,n))}))}return e}function o(e,n){if(null==e)return{};var t,a,i=function(e,n){if(null==e)return{};var t,a,i={},l=Object.keys(e);for(a=0;a<l.length;a++)t=l[a],n.indexOf(t)>=0||(i[t]=e[t]);return i}(e,n);if(Object.getOwnPropertySymbols){var l=Object.getOwnPropertySymbols(e);for(a=0;a<l.length;a++)t=l[a],n.indexOf(t)>=0||Object.prototype.propertyIsEnumerable.call(e,t)&&(i[t]=e[t])}return i}var p=a.createContext({}),s=function(e){var n=a.useContext(p),t=n;return e&&(t="function"==typeof e?e(n):r(r({},n),e)),t},d=function(e){var n=s(e.components);return a.createElement(p.Provider,{value:n},e.children)},c="mdxType",m={inlineCode:"code",wrapper:function(e){var n=e.children;return a.createElement(a.Fragment,{},n)}},u=a.forwardRef((function(e,n){var t=e.components,i=e.mdxType,l=e.originalType,p=e.parentName,d=o(e,["components","mdxType","originalType","parentName"]),c=s(t),u=i,k=c["".concat(p,".").concat(u)]||c[u]||m[u]||l;return t?a.createElement(k,r(r({ref:n},d),{},{components:t})):a.createElement(k,r({ref:n},d))}));function k(e,n){var t=arguments,i=n&&n.mdxType;if("string"==typeof e||i){var l=t.length,r=new Array(l);r[0]=u;var o={};for(var p in n)hasOwnProperty.call(n,p)&&(o[p]=n[p]);o.originalType=e,o[c]="string"==typeof e?e:i,r[1]=o;for(var s=2;s<l;s++)r[s]=t[s];return a.createElement.apply(null,r)}return a.createElement.apply(null,t)}u.displayName="MDXCreateElement"},3781:(e,n,t)=>{t.r(n),t.d(n,{assets:()=>p,contentTitle:()=>r,default:()=>m,frontMatter:()=>l,metadata:()=>o,toc:()=>s});var a=t(7462),i=(t(7294),t(3905));const l={id:"low-level-commands",title:"Low Level Commands"},r=void 0,o={unversionedId:"low-level-commands",id:"low-level-commands",title:"Low Level Commands",description:"esy provides a set of low level commands which enable more configurable",source:"@site/../docs/low-level-commands.md",sourceDirName:".",slug:"/low-level-commands",permalink:"/docs/low-level-commands",draft:!1,editUrl:"https://github.com/esy/esy/tree/master/docs/../docs/low-level-commands.md",tags:[],version:"current",lastUpdatedBy:"Manas",lastUpdatedAt:1693535474,formattedLastUpdatedAt:"Sep 1, 2023",frontMatter:{id:"low-level-commands",title:"Low Level Commands"},sidebar:"docs",previous:{title:"Commands",permalink:"/docs/commands"},next:{title:"Configuration",permalink:"/docs/esy-configuration"}},p={},s=[{value:"Managing installations",id:"managing-installations",level:2},{value:"<code>esy solve</code>",id:"esy-solve",level:3},{value:"<code>esy fetch</code>",id:"esy-fetch",level:3},{value:"Managing build environment",id:"managing-build-environment",level:2},{value:"<code>esy build-dependencies</code>",id:"esy-build-dependencies",level:3},{value:"<code>esy command-exec</code>",id:"esy-command-exec",level:3},{value:"<code>esy print-env</code>",id:"esy-print-env",level:3},{value:"DEPSPEC",id:"depspec",level:2}],d={toc:s},c="wrapper";function m(e){let{components:n,...t}=e;return(0,i.kt)(c,(0,a.Z)({},d,t,{components:n,mdxType:"MDXLayout"}),(0,i.kt)("p",null,"esy provides a set of low level commands which enable more configurable\nworkflows."),(0,i.kt)("p",null,"Such commands are grouped into two concerns:"),(0,i.kt)("ul",null,(0,i.kt)("li",{parentName:"ul"},"Managing installations"),(0,i.kt)("li",{parentName:"ul"},"Managing build environments")),(0,i.kt)("h2",{id:"managing-installations"},"Managing installations"),(0,i.kt)("p",null,"The following commands helps managing installations of dependencies."),(0,i.kt)("p",null,"The end product of an installation procedure is a solution lock (",(0,i.kt)("inlineCode",{parentName:"p"},"esy.lock"),"\ndirectory) which describes the package graph which corresponds to the\nconstraints defined in ",(0,i.kt)("inlineCode",{parentName:"p"},"package.json")," manifest."),(0,i.kt)("p",null,"User typically don't need to run those commands but rather use ",(0,i.kt)("inlineCode",{parentName:"p"},"esy install"),"\ninvocation or ",(0,i.kt)("inlineCode",{parentName:"p"},"esy")," invocation which performs installation procedure as needed."),(0,i.kt)("h3",{id:"esy-solve"},(0,i.kt)("inlineCode",{parentName:"h3"},"esy solve")),(0,i.kt)("p",null,(0,i.kt)("inlineCode",{parentName:"p"},"esy solve")," command performs dependency resolution and produces the solution lock\n(",(0,i.kt)("inlineCode",{parentName:"p"},"esy.lock")," directory). It doesn't fetch package sources."),(0,i.kt)("h3",{id:"esy-fetch"},(0,i.kt)("inlineCode",{parentName:"h3"},"esy fetch")),(0,i.kt)("p",null,(0,i.kt)("inlineCode",{parentName:"p"},"esy fetch")," command fetches package sources as defined in ",(0,i.kt)("inlineCode",{parentName:"p"},"esy.lock")," making\npackage sources available for the next commands in the pipeline."),(0,i.kt)("h2",{id:"managing-build-environment"},"Managing build environment"),(0,i.kt)("p",null,"The following commands operate on a project which has the ",(0,i.kt)("inlineCode",{parentName:"p"},"esy.lock")," produced\nand sources fetched."),(0,i.kt)("h3",{id:"esy-build-dependencies"},(0,i.kt)("inlineCode",{parentName:"h3"},"esy build-dependencies")),(0,i.kt)("p",null,(0,i.kt)("inlineCode",{parentName:"p"},"esy build-dependencies")," command builds dependencies in a given build\nenvironment for a given package:"),(0,i.kt)("pre",null,(0,i.kt)("code",{parentName:"pre",className:"language-bash"},"esy build-dependencies [OPTION]... [PACKAGE]\n")),(0,i.kt)("p",null,"Note that by default only regular packages are built, to build linked packages\none need to pass ",(0,i.kt)("inlineCode",{parentName:"p"},"--all")," command line flag."),(0,i.kt)("p",null,"Arguments:"),(0,i.kt)("ul",null,(0,i.kt)("li",{parentName:"ul"},(0,i.kt)("inlineCode",{parentName:"li"},"PACKAGE")," (optional, default: ",(0,i.kt)("inlineCode",{parentName:"li"},"root"),") Package to build dependencies for.")),(0,i.kt)("p",null,"Options:"),(0,i.kt)("ul",null,(0,i.kt)("li",{parentName:"ul"},(0,i.kt)("p",{parentName:"li"},(0,i.kt)("inlineCode",{parentName:"p"},"--all")," Build all dependencies (including linked packages)")),(0,i.kt)("li",{parentName:"ul"},(0,i.kt)("p",{parentName:"li"},(0,i.kt)("inlineCode",{parentName:"p"},"--release"),' Force to use "esy.build" commands (by default "esy.buildDev"\ncommands are used)'),(0,i.kt)("p",{parentName:"li"},"By default linked packages are built using ",(0,i.kt)("inlineCode",{parentName:"p"},'"esy.buildDev"')," commands defined\nin their corresponding ",(0,i.kt)("inlineCode",{parentName:"p"},"package.json")," manifests, passing ",(0,i.kt)("inlineCode",{parentName:"p"},"--release")," makes\nbuild process use ",(0,i.kt)("inlineCode",{parentName:"p"},'"esy.build"')," commands instead."))),(0,i.kt)("h3",{id:"esy-command-exec"},(0,i.kt)("inlineCode",{parentName:"h3"},"esy command-exec")),(0,i.kt)("p",null,(0,i.kt)("inlineCode",{parentName:"p"},"esy-exec-command")," command executes a command in a given environment:"),(0,i.kt)("pre",null,(0,i.kt)("code",{parentName:"pre",className:"language-bash"},"esy exec-command [OPTION]... PACKAGE COMMAND...\n")),(0,i.kt)("p",null,"Arguments:"),(0,i.kt)("ul",null,(0,i.kt)("li",{parentName:"ul"},(0,i.kt)("p",{parentName:"li"},(0,i.kt)("inlineCode",{parentName:"p"},"COMMAND")," (required) Command to execute within the environment.")),(0,i.kt)("li",{parentName:"ul"},(0,i.kt)("p",{parentName:"li"},(0,i.kt)("inlineCode",{parentName:"p"},"PACKAGE")," (required) Package in which environment execute the command."))),(0,i.kt)("p",null,"Options:"),(0,i.kt)("ul",null,(0,i.kt)("li",{parentName:"ul"},(0,i.kt)("p",{parentName:"li"},(0,i.kt)("inlineCode",{parentName:"p"},"--build-context")," Initialize package's build context before executing the command."),(0,i.kt)("p",{parentName:"li"},"This provides the identical context as when running package build commands.")),(0,i.kt)("li",{parentName:"ul"},(0,i.kt)("p",{parentName:"li"},(0,i.kt)("inlineCode",{parentName:"p"},"--envspec=DEPSPEC")," Define DEPSPEC expression which is used to construct the\nenvironment for the command invocation.")),(0,i.kt)("li",{parentName:"ul"},(0,i.kt)("p",{parentName:"li"},(0,i.kt)("inlineCode",{parentName:"p"},"--include-build-env")," Include build environment.")),(0,i.kt)("li",{parentName:"ul"},(0,i.kt)("p",{parentName:"li"},(0,i.kt)("inlineCode",{parentName:"p"},"--include-current-env")," Include current environment.")),(0,i.kt)("li",{parentName:"ul"},(0,i.kt)("p",{parentName:"li"},(0,i.kt)("inlineCode",{parentName:"p"},"--include-npm-bin")," Include npm bin in ",(0,i.kt)("inlineCode",{parentName:"p"},"$PATH"),"."))),(0,i.kt)("h3",{id:"esy-print-env"},(0,i.kt)("inlineCode",{parentName:"h3"},"esy print-env")),(0,i.kt)("p",null,(0,i.kt)("inlineCode",{parentName:"p"},"esy-print-env")," command prints a configured environment on stdout:"),(0,i.kt)("pre",null,(0,i.kt)("code",{parentName:"pre",className:"language-bash"},"esy print-env [OPTION]... PACKAGE\n")),(0,i.kt)("p",null,"Arguments:"),(0,i.kt)("ul",null,(0,i.kt)("li",{parentName:"ul"},(0,i.kt)("inlineCode",{parentName:"li"},"PACKAGE")," (required) Package in which environment execute the command.")),(0,i.kt)("p",null,"Options:"),(0,i.kt)("ul",null,(0,i.kt)("li",{parentName:"ul"},(0,i.kt)("p",{parentName:"li"},(0,i.kt)("inlineCode",{parentName:"p"},"--envspec=DEPSPEC")," Define DEPSPEC expression which is used to construct the\nenvironment for the command invocation.")),(0,i.kt)("li",{parentName:"ul"},(0,i.kt)("p",{parentName:"li"},(0,i.kt)("inlineCode",{parentName:"p"},"--include-build-env")," Include build environment. This includes some special\n",(0,i.kt)("inlineCode",{parentName:"p"},"$cur__*")," envirironment variables, as well as environment variables configured\nin the ",(0,i.kt)("inlineCode",{parentName:"p"},"esy.buildEnv")," section of the package config.")),(0,i.kt)("li",{parentName:"ul"},(0,i.kt)("p",{parentName:"li"},(0,i.kt)("inlineCode",{parentName:"p"},"--include-current-env")," Include current environment.")),(0,i.kt)("li",{parentName:"ul"},(0,i.kt)("p",{parentName:"li"},(0,i.kt)("inlineCode",{parentName:"p"},"--include-npm-bin")," Include npm bin in ",(0,i.kt)("inlineCode",{parentName:"p"},"$PATH"),".")),(0,i.kt)("li",{parentName:"ul"},(0,i.kt)("p",{parentName:"li"},(0,i.kt)("inlineCode",{parentName:"p"},"--json")," Format output as JSON"))),(0,i.kt)("h2",{id:"depspec"},"DEPSPEC"),(0,i.kt)("p",null,"Some commands allow to define how an environment is constructed for each package\nbased on other packages in a dependency graph (see ",(0,i.kt)("inlineCode",{parentName:"p"},"--envspec")," command option\ndescribed above). This is done via DEPSPEC expressions."),(0,i.kt)("p",null,"There are the following constructs available in DEPSPEC:"),(0,i.kt)("ul",null,(0,i.kt)("li",{parentName:"ul"},(0,i.kt)("p",{parentName:"li"},(0,i.kt)("inlineCode",{parentName:"p"},"self")," refers to the current package, for which the environment is being constructed.")),(0,i.kt)("li",{parentName:"ul"},(0,i.kt)("p",{parentName:"li"},(0,i.kt)("inlineCode",{parentName:"p"},"root")," refers to the root package in an esy project.")),(0,i.kt)("li",{parentName:"ul"},(0,i.kt)("p",{parentName:"li"},(0,i.kt)("inlineCode",{parentName:"p"},"dependencies(PKG)")," refers to a set of ",(0,i.kt)("inlineCode",{parentName:"p"},'"dependencies"')," of ",(0,i.kt)("inlineCode",{parentName:"p"},"PKG")," package.")),(0,i.kt)("li",{parentName:"ul"},(0,i.kt)("p",{parentName:"li"},(0,i.kt)("inlineCode",{parentName:"p"},"devDependencies(PKG)")," refers to a set of ",(0,i.kt)("inlineCode",{parentName:"p"},'"devDependencies"')," of ",(0,i.kt)("inlineCode",{parentName:"p"},"PKG")," package.")),(0,i.kt)("li",{parentName:"ul"},(0,i.kt)("p",{parentName:"li"},(0,i.kt)("inlineCode",{parentName:"p"},"EXPR1 + EXPR2")," refers to a set of packages found in ",(0,i.kt)("inlineCode",{parentName:"p"},"EXPR1")," or ",(0,i.kt)("inlineCode",{parentName:"p"},"EXPR2"),"\n(union)."))),(0,i.kt)("p",null,"Examples:"),(0,i.kt)("ul",null,(0,i.kt)("li",{parentName:"ul"},(0,i.kt)("p",{parentName:"li"},"Dependencies of the current package:"),(0,i.kt)("pre",{parentName:"li"},(0,i.kt)("code",{parentName:"pre",className:"language-bash"},"dependencies(self)\n")),(0,i.kt)("p",{parentName:"li"},"This constructs the environment which is analogous to the environment used to\nbuild packages.")),(0,i.kt)("li",{parentName:"ul"},(0,i.kt)("p",{parentName:"li"},"Dev dependencies of the root package:"),(0,i.kt)("pre",{parentName:"li"},(0,i.kt)("code",{parentName:"pre",className:"language-bash"},"devDependencies(root)\n"))),(0,i.kt)("li",{parentName:"ul"},(0,i.kt)("p",{parentName:"li"},"Dependencies of the current package and the package itself:"),(0,i.kt)("pre",{parentName:"li"},(0,i.kt)("code",{parentName:"pre",className:"language-bash"},"dependencies(self) + self\n")),(0,i.kt)("p",{parentName:"li"},"This constructs the environment which is analogous to the environment used in\n",(0,i.kt)("inlineCode",{parentName:"p"},"esy x CMD")," invocations."))))}m.isMDXComponent=!0}}]);