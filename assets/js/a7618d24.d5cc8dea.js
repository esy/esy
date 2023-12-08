"use strict";(self.webpackChunksite_v_3=self.webpackChunksite_v_3||[]).push([[3908],{5013:(e,n,i)=>{i.r(n),i.d(n,{assets:()=>o,contentTitle:()=>c,default:()=>h,frontMatter:()=>d,metadata:()=>l,toc:()=>t});var s=i(5893),r=i(1151);const d={id:"environment",title:"Environment"},c=void 0,l={id:"environment",title:"Environment",description:"- Build Environment",source:"@site/../docs/environment.md",sourceDirName:".",slug:"/environment",permalink:"/docs/environment",draft:!1,unlisted:!1,editUrl:"https://github.com/esy/esy/tree/master/docs/../docs/environment.md",tags:[],version:"current",lastUpdatedBy:"prometheansacrifice",lastUpdatedAt:1702029753,formattedLastUpdatedAt:"Dec 8, 2023",frontMatter:{id:"environment",title:"Environment"},sidebar:"docs",previous:{title:"Project Configuration",permalink:"/docs/configuration"},next:{title:"Commands",permalink:"/docs/commands"}},o={},t=[{value:"Build Environment",id:"build-environment",level:2},{value:"Command Environment",id:"command-environment",level:2},{value:"Test Environment (exported environment)",id:"test-environment-exported-environment",level:2},{value:"Variable substitution syntax",id:"variable-substitution-syntax",level:2}];function a(e){const n={a:"a",code:"code",h2:"h2",li:"li",ol:"ol",p:"p",pre:"pre",strong:"strong",ul:"ul",...(0,r.a)(),...e.components};return(0,s.jsxs)(s.Fragment,{children:[(0,s.jsxs)(n.ul,{children:["\n",(0,s.jsx)(n.li,{children:(0,s.jsx)(n.a,{href:"#build-environment",children:"Build Environment"})}),"\n",(0,s.jsx)(n.li,{children:(0,s.jsx)(n.a,{href:"#command-environment",children:"Command Environment"})}),"\n",(0,s.jsx)(n.li,{children:(0,s.jsx)(n.a,{href:"#test-environment-exported-environment",children:"Test Environment (exported environment)"})}),"\n",(0,s.jsx)(n.li,{children:(0,s.jsx)(n.a,{href:"#variable-substitution-syntax",children:"Variable substitution syntax"})}),"\n"]}),"\n",(0,s.jsx)(n.p,{children:"For each project esy manages:"}),"\n",(0,s.jsxs)(n.ul,{children:["\n",(0,s.jsxs)(n.li,{children:["\n",(0,s.jsxs)(n.p,{children:[(0,s.jsx)(n.strong,{children:"build environment"})," \u2014 an environment which is used to build the project"]}),"\n"]}),"\n",(0,s.jsxs)(n.li,{children:["\n",(0,s.jsxs)(n.p,{children:[(0,s.jsx)(n.strong,{children:"command environment"})," \u2014 an environment which is used running text editors/IDE\nand for general testing of the built artfiacts"]}),"\n"]}),"\n",(0,s.jsxs)(n.li,{children:["\n",(0,s.jsxs)(n.p,{children:[(0,s.jsx)(n.strong,{children:"test environment"})," \u2014 an environment which includes the current package's\ninstallation directories and its exported environment. This is useful if you need\nan environment in which the current application appears installed."]}),"\n"]}),"\n"]}),"\n",(0,s.jsx)(n.p,{children:"Each environment consists of two parts:"}),"\n",(0,s.jsxs)(n.ol,{children:["\n",(0,s.jsxs)(n.li,{children:["\n",(0,s.jsx)(n.p,{children:"Base environment provided by esy."}),"\n"]}),"\n",(0,s.jsxs)(n.li,{children:["\n",(0,s.jsx)(n.p,{children:"Environment exported from the sandbox dependencies. There are several types\nof dependencies esy can understand:"}),"\n",(0,s.jsxs)(n.ol,{children:["\n",(0,s.jsxs)(n.li,{children:["\n",(0,s.jsxs)(n.p,{children:[(0,s.jsx)(n.strong,{children:"Regular dependencies"})," are dependencies which are needed at runtime.\nThey are listed in ",(0,s.jsx)(n.code,{children:'"dependencies"'})," key of the ",(0,s.jsx)(n.code,{children:"package.json"}),"."]}),"\n"]}),"\n",(0,s.jsxs)(n.li,{children:["\n",(0,s.jsxs)(n.p,{children:[(0,s.jsx)(n.strong,{children:"Development time dependencies"})," are dependencies which are needed only\nduring development. They are listed in ",(0,s.jsx)(n.code,{children:'"devDependencies"'})," key of the\n",(0,s.jsx)(n.code,{children:"package.json"}),". Examples: ",(0,s.jsx)(n.code,{children:"@opam/merlin"}),", ",(0,s.jsx)(n.code,{children:"@opam/ocamlformat"})," and so on."]}),"\n"]}),"\n",(0,s.jsxs)(n.li,{children:["\n",(0,s.jsxs)(n.p,{children:[(0,s.jsx)(n.strong,{children:"Build time dependencies"})," (NOT IMPLEMENTED) are dependencies which are\nonly needed during the build of the project. Support for those is ",(0,s.jsx)(n.strong,{children:"not\nimplemented"})," currently. The workaround is to declare such dependencies as\nregular dependencies for the time being."]}),"\n"]}),"\n"]}),"\n"]}),"\n"]}),"\n",(0,s.jsx)(n.h2,{id:"build-environment",children:"Build Environment"}),"\n",(0,s.jsx)(n.p,{children:"The following environment is provided by esy:"}),"\n",(0,s.jsxs)(n.ul,{children:["\n",(0,s.jsxs)(n.li,{children:["\n",(0,s.jsxs)(n.p,{children:[(0,s.jsx)(n.code,{children:"$SHELL"})," is set to ",(0,s.jsx)(n.code,{children:"env -i /bin/bash --norc --noprofile"})," so each build is\nexecuted in an environment clear from user customizations usually found in\n",(0,s.jsx)(n.code,{children:".profile"})," or other configuration files."]}),"\n"]}),"\n",(0,s.jsxs)(n.li,{children:["\n",(0,s.jsxs)(n.p,{children:[(0,s.jsx)(n.code,{children:"$PATH"})," contains all regular dependencies' ",(0,s.jsx)(n.code,{children:"bin/"})," directories."]}),"\n"]}),"\n",(0,s.jsxs)(n.li,{children:["\n",(0,s.jsxs)(n.p,{children:[(0,s.jsx)(n.code,{children:"$MAN_PATH"})," contains all regular dependencies' ",(0,s.jsx)(n.code,{children:"man/"})," directories."]}),"\n"]}),"\n",(0,s.jsxs)(n.li,{children:["\n",(0,s.jsxs)(n.p,{children:[(0,s.jsx)(n.code,{children:"$OCAMLPATH"})," contains all regular dependencies' ",(0,s.jsx)(n.code,{children:"lib/"})," directories."]}),"\n"]}),"\n"]}),"\n",(0,s.jsxs)(n.p,{children:["Each regular dependency of the project can also contribute to the environment\nthrough ",(0,s.jsx)(n.code,{children:'"esy.exportedEnv"'})," key in ",(0,s.jsx)(n.code,{children:"package.json"}),". See ",(0,s.jsx)(n.a,{href:"configuration.md",children:"Project\nConfiguration"})," for details."]}),"\n",(0,s.jsx)(n.h2,{id:"command-environment",children:"Command Environment"}),"\n",(0,s.jsx)(n.p,{children:"The following environment is provided by esy:"}),"\n",(0,s.jsxs)(n.ul,{children:["\n",(0,s.jsxs)(n.li,{children:["\n",(0,s.jsxs)(n.p,{children:[(0,s.jsx)(n.code,{children:"$PATH"})," contains all regular ",(0,s.jsx)(n.strong,{children:"and development"})," time dependencies' ",(0,s.jsx)(n.code,{children:"bin/"}),"\ndirectories."]}),"\n"]}),"\n",(0,s.jsxs)(n.li,{children:["\n",(0,s.jsxs)(n.p,{children:[(0,s.jsx)(n.code,{children:"$MAN_PATH"})," contains all regular ",(0,s.jsx)(n.strong,{children:"and development"})," dependencies' ",(0,s.jsx)(n.code,{children:"man/"}),"\ndirectories."]}),"\n"]}),"\n",(0,s.jsxs)(n.li,{children:["\n",(0,s.jsxs)(n.p,{children:[(0,s.jsx)(n.code,{children:"$OCAMLPATH"})," contains all regular ",(0,s.jsx)(n.strong,{children:"and development"})," dependencies' ",(0,s.jsx)(n.code,{children:"lib/"}),"\ndirectories."]}),"\n"]}),"\n"]}),"\n",(0,s.jsxs)(n.p,{children:["Each regular ",(0,s.jsx)(n.strong,{children:"and development"})," dependency of the project can also contribute to the\nenvironment through ",(0,s.jsx)(n.code,{children:'"esy.exportedEnv"'})," key in ",(0,s.jsx)(n.code,{children:"package.json"}),". See ",(0,s.jsx)(n.a,{href:"configuration.md",children:"Project\nConfiguration"})," for details."]}),"\n",(0,s.jsx)(n.h2,{id:"test-environment-exported-environment",children:"Test Environment (exported environment)"}),"\n",(0,s.jsx)(n.p,{children:"Some packages need to set environment variables in the environment of the package consuming them. Sometimes, a root package may need to set some variables in the sandbox if the binaries need them."}),"\n",(0,s.jsxs)(n.p,{children:["These environment variables are 'exported' using the ",(0,s.jsx)(n.code,{children:"exportedEnv"}),"."]}),"\n",(0,s.jsx)(n.p,{children:"By default, the following environment is provided by esy:"}),"\n",(0,s.jsxs)(n.ul,{children:["\n",(0,s.jsxs)(n.li,{children:["\n",(0,s.jsxs)(n.p,{children:[(0,s.jsx)(n.code,{children:"$PATH"})," contains all regular time dependencies' ",(0,s.jsx)(n.code,{children:"bin/"}),"\ndirectories ",(0,s.jsx)(n.strong,{children:"and project's own"})," ",(0,s.jsx)(n.code,{children:"bin/"})," directory."]}),"\n"]}),"\n",(0,s.jsxs)(n.li,{children:["\n",(0,s.jsxs)(n.p,{children:[(0,s.jsx)(n.code,{children:"$MAN_PATH"})," contains all regular dependencies' ",(0,s.jsx)(n.code,{children:"man/"}),"\ndirectories ",(0,s.jsx)(n.strong,{children:"and project's own"})," ",(0,s.jsx)(n.code,{children:"man/"})," directory."]}),"\n"]}),"\n",(0,s.jsxs)(n.li,{children:["\n",(0,s.jsxs)(n.p,{children:[(0,s.jsx)(n.code,{children:"$OCAMLPATH"})," contains all regular dependencies' ",(0,s.jsx)(n.code,{children:"lib/"}),"\ndirectories  ",(0,s.jsx)(n.strong,{children:"and project's own"})," ",(0,s.jsx)(n.code,{children:"lib/"})," directory."]}),"\n"]}),"\n"]}),"\n",(0,s.jsxs)(n.p,{children:["Each regular dependency of the project ",(0,s.jsx)(n.strong,{children:"and the project itself"})," can also\ncontribute to the environment through ",(0,s.jsx)(n.code,{children:'"esy.exportedEnv"'})," key in ",(0,s.jsx)(n.code,{children:"package.json"}),".\nSee ",(0,s.jsx)(n.a,{href:"/docs/configuration",children:"Project Configuration"})," for details."]}),"\n",(0,s.jsx)(n.h2,{id:"variable-substitution-syntax",children:"Variable substitution syntax"}),"\n",(0,s.jsxs)(n.p,{children:["Your ",(0,s.jsx)(n.code,{children:"package.json"}),"'s ",(0,s.jsx)(n.code,{children:"esy"}),' configuration can include "interpolation" regions\nwritten as ',(0,s.jsx)(n.code,{children:"#{ }"}),", where ",(0,s.jsx)(n.code,{children:"esy"}),' "variables" can be used which will automatically\nbe substituted with their corresponding values.']}),"\n",(0,s.jsxs)(n.p,{children:["For example, if you have a package named ",(0,s.jsx)(n.code,{children:"@company/widget-factory"})," at version\n",(0,s.jsx)(n.code,{children:"1.2.0"}),", then its ",(0,s.jsx)(n.code,{children:"esy.build"})," field in ",(0,s.jsx)(n.code,{children:"package.json"})," could be specified as:"]}),"\n",(0,s.jsx)(n.pre,{children:(0,s.jsx)(n.code,{className:"language-json",children:'   "build": "make #{@company/widget-factory.version}",\n'})}),"\n",(0,s.jsxs)(n.p,{children:["and ",(0,s.jsx)(n.code,{children:"esy"})," will ensure that the build command is interpreted as ",(0,s.jsx)(n.code,{children:'"make 1.2.0"'}),".\nIn this example the interpolation region includes just one ",(0,s.jsx)(n.code,{children:"esy"})," variable\n",(0,s.jsx)(n.code,{children:"@company/widget-factory.version"})," - which is substituted with the version number\nfor the ",(0,s.jsx)(n.code,{children:"@company/widget-factory"})," package."]}),"\n",(0,s.jsxs)(n.p,{children:["Package specific variables are prefixed with their package name, followed\nby an ",(0,s.jsx)(n.code,{children:"esy"}),' "property" of that package such as ',(0,s.jsx)(n.code,{children:".version"})," or ",(0,s.jsx)(n.code,{children:".lib"}),"."]}),"\n",(0,s.jsxs)(n.p,{children:[(0,s.jsx)(n.code,{children:"esy"})," also provides some other built in variables which help with path and environment\nmanipulation in a cross platform manner."]}),"\n",(0,s.jsx)(n.p,{children:(0,s.jsx)(n.strong,{children:"Supported Variable Substitutions:"})}),"\n",(0,s.jsx)(n.p,{children:"Those variables refer to the values defined for the current package:"}),"\n",(0,s.jsxs)(n.ul,{children:["\n",(0,s.jsxs)(n.li,{children:[(0,s.jsx)(n.code,{children:"self.name"})," represents the name of the package"]}),"\n",(0,s.jsxs)(n.li,{children:[(0,s.jsx)(n.code,{children:"self.version"})," represents the version of the package (as defined in its\n",(0,s.jsx)(n.code,{children:"package.json"}),")"]}),"\n",(0,s.jsxs)(n.li,{children:[(0,s.jsx)(n.code,{children:"self.root"})," is the package source root"]}),"\n",(0,s.jsxs)(n.li,{children:[(0,s.jsx)(n.code,{children:"self.target_dir"})," is the package build directory"]}),"\n",(0,s.jsxs)(n.li,{children:[(0,s.jsx)(n.code,{children:"self.jobs"})," is the number of processors the build system can used parallely. The name ",(0,s.jsx)(n.code,{children:"jobs"})," is inspired by it counterpart in opam."]}),"\n",(0,s.jsxs)(n.li,{children:[(0,s.jsx)(n.code,{children:"self.install"})," is the package installation directory, there are also\nvariables defined which refer to common subdirectories of ",(0,s.jsx)(n.code,{children:"self.install"}),":","\n",(0,s.jsxs)(n.ul,{children:["\n",(0,s.jsx)(n.li,{children:(0,s.jsx)(n.code,{children:"self.bin"})}),"\n",(0,s.jsx)(n.li,{children:(0,s.jsx)(n.code,{children:"self.sbin"})}),"\n",(0,s.jsx)(n.li,{children:(0,s.jsx)(n.code,{children:"self.lib"})}),"\n",(0,s.jsx)(n.li,{children:(0,s.jsx)(n.code,{children:"self.man"})}),"\n",(0,s.jsx)(n.li,{children:(0,s.jsx)(n.code,{children:"self.doc"})}),"\n",(0,s.jsx)(n.li,{children:(0,s.jsx)(n.code,{children:"self.stublibs"})}),"\n",(0,s.jsx)(n.li,{children:(0,s.jsx)(n.code,{children:"self.toplevel"})}),"\n",(0,s.jsx)(n.li,{children:(0,s.jsx)(n.code,{children:"self.share"})}),"\n",(0,s.jsx)(n.li,{children:(0,s.jsx)(n.code,{children:"self.etc"})}),"\n"]}),"\n"]}),"\n"]}),"\n",(0,s.jsxs)(n.p,{children:["Note that for packages which have ",(0,s.jsx)(n.code,{children:"buildsInSource: true"})," esy copies sources into ",(0,s.jsx)(n.code,{children:"self.target_dir"})," and therefore values of ",(0,s.jsx)(n.code,{children:"self.root"})," and ",(0,s.jsx)(n.code,{children:"self.target_dir"})," are the same."]}),"\n",(0,s.jsxs)(n.p,{children:["You can refer to the values defined for other packages which are direct\ndependencies by using the respective ",(0,s.jsx)(n.code,{children:"package-name."})," prefix. Available variables are the same:"]}),"\n",(0,s.jsxs)(n.ul,{children:["\n",(0,s.jsx)(n.li,{children:(0,s.jsx)(n.code,{children:"package-name.name"})}),"\n",(0,s.jsx)(n.li,{children:(0,s.jsx)(n.code,{children:"package-name.version"})}),"\n",(0,s.jsx)(n.li,{children:(0,s.jsx)(n.code,{children:"package-name.root"})}),"\n",(0,s.jsx)(n.li,{children:(0,s.jsx)(n.code,{children:"package-name.target_dir"})}),"\n",(0,s.jsxs)(n.li,{children:[(0,s.jsx)(n.code,{children:"package-name.install"}),"\n",(0,s.jsxs)(n.ul,{children:["\n",(0,s.jsx)(n.li,{children:(0,s.jsx)(n.code,{children:"package-name.bin"})}),"\n",(0,s.jsx)(n.li,{children:(0,s.jsx)(n.code,{children:"package-name.sbin"})}),"\n",(0,s.jsx)(n.li,{children:(0,s.jsx)(n.code,{children:"package-name.lib"})}),"\n",(0,s.jsx)(n.li,{children:(0,s.jsx)(n.code,{children:"package-name.man"})}),"\n",(0,s.jsx)(n.li,{children:(0,s.jsx)(n.code,{children:"package-name.doc"})}),"\n",(0,s.jsx)(n.li,{children:(0,s.jsx)(n.code,{children:"package-name.stublibs"})}),"\n",(0,s.jsx)(n.li,{children:(0,s.jsx)(n.code,{children:"package-name.toplevel"})}),"\n",(0,s.jsx)(n.li,{children:(0,s.jsx)(n.code,{children:"package-name.share"})}),"\n",(0,s.jsx)(n.li,{children:(0,s.jsx)(n.code,{children:"package-name.etc"})}),"\n"]}),"\n"]}),"\n"]}),"\n",(0,s.jsx)(n.p,{children:'The following constructs are also allowed inside "interpolation" regions:'}),"\n",(0,s.jsxs)(n.ul,{children:["\n",(0,s.jsxs)(n.li,{children:[(0,s.jsx)(n.code,{children:"$PATH"}),", ",(0,s.jsx)(n.code,{children:"$cur__bin"})," : environment variable references"]}),"\n",(0,s.jsxs)(n.li,{children:[(0,s.jsx)(n.code,{children:"'hello'"}),", ",(0,s.jsx)(n.code,{children:"'lib'"})," : string literals"]}),"\n",(0,s.jsxs)(n.li,{children:[(0,s.jsx)(n.code,{children:"/"})," : path separator (substituted with the platform's path separator)"]}),"\n",(0,s.jsxs)(n.li,{children:[(0,s.jsx)(n.code,{children:":"})," : env var value separator (substituted with platform's env var separator ",(0,s.jsx)(n.code,{children:":"}),"/",(0,s.jsx)(n.code,{children:";"}),")."]}),"\n"]}),"\n",(0,s.jsxs)(n.p,{children:["You can join many of these ",(0,s.jsx)(n.code,{children:"esy"})," variables together inside of an interpolation region\nby separating the variables with spaces. The entire interpolation region will be substituted\nwith the concatenation of the space separated ",(0,s.jsx)(n.code,{children:"esy"})," variables."]}),"\n",(0,s.jsxs)(n.p,{children:["White space separating the variables are not included in the concatenation, If\nyou need to insert a literal white space, use ",(0,s.jsx)(n.code,{children:"' '"})," string literal."]}),"\n",(0,s.jsx)(n.p,{children:"Examples:"}),"\n",(0,s.jsxs)(n.ul,{children:["\n",(0,s.jsxs)(n.li,{children:["\n",(0,s.jsx)(n.p,{children:(0,s.jsx)(n.code,{children:'"#{pkg.bin : $PATH}"'})}),"\n"]}),"\n",(0,s.jsxs)(n.li,{children:["\n",(0,s.jsx)(n.p,{children:(0,s.jsx)(n.code,{children:"\"#{pkg.lib / 'stublibs' : $CAML_LD_LIBRARY_PATH}\""})}),"\n"]}),"\n"]})]})}function h(e={}){const{wrapper:n}={...(0,r.a)(),...e.components};return n?(0,s.jsx)(n,{...e,children:(0,s.jsx)(a,{...e})}):a(e)}},1151:(e,n,i)=>{i.d(n,{Z:()=>l,a:()=>c});var s=i(7294);const r={},d=s.createContext(r);function c(e){const n=s.useContext(d);return s.useMemo((function(){return"function"==typeof e?e(n):{...n,...e}}),[n,e])}function l(e){let n;return n=e.disableParentContext?"function"==typeof e.components?e.components(r):e.components||r:c(e.components),s.createElement(d.Provider,{value:n},e.children)}}}]);