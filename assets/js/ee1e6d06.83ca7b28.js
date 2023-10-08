"use strict";(self.webpackChunksite_v_3=self.webpackChunksite_v_3||[]).push([[6364],{3905:(e,n,t)=>{t.d(n,{Zo:()=>p,kt:()=>f});var o=t(7294);function a(e,n,t){return n in e?Object.defineProperty(e,n,{value:t,enumerable:!0,configurable:!0,writable:!0}):e[n]=t,e}function i(e,n){var t=Object.keys(e);if(Object.getOwnPropertySymbols){var o=Object.getOwnPropertySymbols(e);n&&(o=o.filter((function(n){return Object.getOwnPropertyDescriptor(e,n).enumerable}))),t.push.apply(t,o)}return t}function r(e){for(var n=1;n<arguments.length;n++){var t=null!=arguments[n]?arguments[n]:{};n%2?i(Object(t),!0).forEach((function(n){a(e,n,t[n])})):Object.getOwnPropertyDescriptors?Object.defineProperties(e,Object.getOwnPropertyDescriptors(t)):i(Object(t)).forEach((function(n){Object.defineProperty(e,n,Object.getOwnPropertyDescriptor(t,n))}))}return e}function l(e,n){if(null==e)return{};var t,o,a=function(e,n){if(null==e)return{};var t,o,a={},i=Object.keys(e);for(o=0;o<i.length;o++)t=i[o],n.indexOf(t)>=0||(a[t]=e[t]);return a}(e,n);if(Object.getOwnPropertySymbols){var i=Object.getOwnPropertySymbols(e);for(o=0;o<i.length;o++)t=i[o],n.indexOf(t)>=0||Object.prototype.propertyIsEnumerable.call(e,t)&&(a[t]=e[t])}return a}var d=o.createContext({}),s=function(e){var n=o.useContext(d),t=n;return e&&(t="function"==typeof e?e(n):r(r({},n),e)),t},p=function(e){var n=s(e.components);return o.createElement(d.Provider,{value:n},e.children)},c="mdxType",u={inlineCode:"code",wrapper:function(e){var n=e.children;return o.createElement(o.Fragment,{},n)}},m=o.forwardRef((function(e,n){var t=e.components,a=e.mdxType,i=e.originalType,d=e.parentName,p=l(e,["components","mdxType","originalType","parentName"]),c=s(t),m=a,f=c["".concat(d,".").concat(m)]||c[m]||u[m]||i;return t?o.createElement(f,r(r({ref:n},p),{},{components:t})):o.createElement(f,r({ref:n},p))}));function f(e,n){var t=arguments,a=n&&n.mdxType;if("string"==typeof e||a){var i=t.length,r=new Array(i);r[0]=m;var l={};for(var d in n)hasOwnProperty.call(n,d)&&(l[d]=n[d]);l.originalType=e,l[c]="string"==typeof e?e:a,r[1]=l;for(var s=2;s<i;s++)r[s]=t[s];return o.createElement.apply(null,r)}return o.createElement.apply(null,t)}m.displayName="MDXCreateElement"},9718:(e,n,t)=>{t.r(n),t.d(n,{assets:()=>d,contentTitle:()=>r,default:()=>u,frontMatter:()=>i,metadata:()=>l,toc:()=>s});var o=t(7462),a=(t(7294),t(3905));const i={id:"multiple-sandboxes",title:"Multiple Project Sandboxes"},r=void 0,l={unversionedId:"multiple-sandboxes",id:"multiple-sandboxes",title:"Multiple Project Sandboxes",description:"Sometimes it is useful to configure multiple sandboxes per project:",source:"@site/../docs/multiple-sandboxes.md",sourceDirName:".",slug:"/multiple-sandboxes",permalink:"/docs/multiple-sandboxes",draft:!1,editUrl:"https://github.com/esy/esy/tree/master/docs/../docs/multiple-sandboxes.md",tags:[],version:"current",lastUpdatedBy:"ducdetronquito",lastUpdatedAt:1696763773,formattedLastUpdatedAt:"Oct 8, 2023",frontMatter:{id:"multiple-sandboxes",title:"Multiple Project Sandboxes"},sidebar:"docs",previous:{title:"Community",permalink:"/docs/community"},next:{title:"Building npm Releases",permalink:"/docs/npm-release"}},d={},s=[{value:"Configure multiple sandboxes",id:"configure-multiple-sandboxes",level:2},{value:"Sandbox configuration overrides",id:"sandbox-configuration-overrides",level:2},{value:"<code>build</code>",id:"build",level:3},{value:"<code>install</code>",id:"install",level:3},{value:"<code>exportedEnv</code>",id:"exportedenv",level:3},{value:"<code>exportedEnvOverride</code>",id:"exportedenvoverride",level:3},{value:"<code>buildEnv</code>",id:"buildenv",level:3},{value:"<code>buildEnvOverride</code>",id:"buildenvoverride",level:3},{value:"<code>dependencies</code>",id:"dependencies",level:3},{value:"<code>devDependencies</code>",id:"devdependencies",level:3},{value:"<code>resolutions</code>",id:"resolutions",level:3}],p={toc:s},c="wrapper";function u(e){let{components:n,...t}=e;return(0,a.kt)(c,(0,o.Z)({},p,t,{components:n,mdxType:"MDXLayout"}),(0,a.kt)("p",null,"Sometimes it is useful to configure multiple sandboxes per project:"),(0,a.kt)("ul",null,(0,a.kt)("li",{parentName:"ul"},"to build a project with a different compiler version"),(0,a.kt)("li",{parentName:"ul"},"to try a project with a different set of dependencies installed"),(0,a.kt)("li",{parentName:"ul"},"to build a project using differeng settings configured via environment\nvariables")),(0,a.kt)("p",null,"It is inconvenient to modify ",(0,a.kt)("inlineCode",{parentName:"p"},"package.json")," and reinstall dependencies each time\nyou want to work in a different sandbox configuration."),(0,a.kt)("p",null,"To streamline this esy provides an ability to have multiple sandbox\nconfigurations per project."),(0,a.kt)("h2",{id:"configure-multiple-sandboxes"},"Configure multiple sandboxes"),(0,a.kt)("p",null,"Put ",(0,a.kt)("inlineCode",{parentName:"p"},"ocaml-4.6.json")," file into the project directory."),(0,a.kt)("blockquote",null,(0,a.kt)("p",{parentName:"blockquote"},(0,a.kt)("inlineCode",{parentName:"p"},"ocaml-4.6")," can be any other name you like for your sandbox config:"),(0,a.kt)("ul",{parentName:"blockquote"},(0,a.kt)("li",{parentName:"ul"},(0,a.kt)("inlineCode",{parentName:"li"},"with-ocaml-4.6.json")),(0,a.kt)("li",{parentName:"ul"},(0,a.kt)("inlineCode",{parentName:"li"},"debug-build.json")))),(0,a.kt)("p",null,(0,a.kt)("inlineCode",{parentName:"p"},"ocaml-4.6.json")," file should have the same format as ",(0,a.kt)("inlineCode",{parentName:"p"},"package.json")," but can have\ndifferent configuration for ",(0,a.kt)("inlineCode",{parentName:"p"},"dependencies"),", ",(0,a.kt)("inlineCode",{parentName:"p"},"devDependencies"),", ",(0,a.kt)("inlineCode",{parentName:"p"},"esy.build")," or\nother fields described in ",(0,a.kt)("a",{parentName:"p",href:"/docs/configuration"},"Project Configuration"),"."),(0,a.kt)("p",null,"For example:"),(0,a.kt)("pre",null,(0,a.kt)("code",{parentName:"pre",className:"language-json"},'{\n  ...\n  "devDependencies": {\n    "ocaml": "~4.6.0"\n  }\n  ...\n}\n')),(0,a.kt)("p",null,"To instruct esy to work with ",(0,a.kt)("inlineCode",{parentName:"p"},"ocaml-4.6.json")," sandbox configuration (instead of\ndefault ",(0,a.kt)("inlineCode",{parentName:"p"},"package.json"),") you can use ",(0,a.kt)("inlineCode",{parentName:"p"},"@ocaml-4.6")," sandbox selector:"),(0,a.kt)("ul",null,(0,a.kt)("li",{parentName:"ul"},(0,a.kt)("p",{parentName:"li"},"Install the dependencies of the ",(0,a.kt)("inlineCode",{parentName:"p"},"ocaml-4.6")," sandbox:"),(0,a.kt)("pre",{parentName:"li"},(0,a.kt)("code",{parentName:"pre",className:"language-shell"},"esy @ocaml-4.6 install\n"))),(0,a.kt)("li",{parentName:"ul"},(0,a.kt)("p",{parentName:"li"},"Build the ",(0,a.kt)("inlineCode",{parentName:"p"},"ocaml-4.6")," sandbox:"),(0,a.kt)("pre",{parentName:"li"},(0,a.kt)("code",{parentName:"pre",className:"language-shell"},"esy @ocaml-4.6 build\n"))),(0,a.kt)("li",{parentName:"ul"},(0,a.kt)("p",{parentName:"li"},"Run a command with the ",(0,a.kt)("inlineCode",{parentName:"p"},"ocaml-4.6")," sandbox environment:"),(0,a.kt)("pre",{parentName:"li"},(0,a.kt)("code",{parentName:"pre",className:"language-shell"},"esy @ocaml-4.6 which ocaml\n")))),(0,a.kt)("blockquote",null,(0,a.kt)("p",{parentName:"blockquote"},"Note that sandbox selector ",(0,a.kt)("inlineCode",{parentName:"p"},"@<sandbox-name>")," should be the first argument to\n",(0,a.kt)("inlineCode",{parentName:"p"},"esy")," command, otherwise it is treated as an option to a subcommand and won't\nhave the desired effect.")),(0,a.kt)("h2",{id:"sandbox-configuration-overrides"},"Sandbox configuration overrides"),(0,a.kt)("p",null,"When sandbox configurations differ just by few configuration parameters it is\ntoo much boilerplate to copy over all ",(0,a.kt)("inlineCode",{parentName:"p"},"package.json")," fields to a new sandbox\nconfiguration."),(0,a.kt)("p",null,"It is possible to use sandbox configuration overrides to aleviate the need in\nsuch boilerplate."),(0,a.kt)("p",null,"Overrides have the following format:"),(0,a.kt)("pre",null,(0,a.kt)("code",{parentName:"pre",className:"language-json"},'{\n  "source": "./package.json",\n  "override": {\n    <override-fields>\n  }\n}\n')),(0,a.kt)("p",null,"Where ",(0,a.kt)("inlineCode",{parentName:"p"},"source")," key defines the origin configuration which is being overriden\nwith the fields from ",(0,a.kt)("inlineCode",{parentName:"p"},"override")," key."),(0,a.kt)("p",null,"Not everything can be overriden and ",(0,a.kt)("inlineCode",{parentName:"p"},"<override-fields>")," can contain one or more\nof the following keys."),(0,a.kt)("h3",{id:"build"},(0,a.kt)("inlineCode",{parentName:"h3"},"build")),(0,a.kt)("p",null,"This replaces ",(0,a.kt)("a",{parentName:"p",href:"/docs/configuration#esybuild"},"esy.build")," commands of the origin\nsandbox configuration:"),(0,a.kt)("pre",null,(0,a.kt)("code",{parentName:"pre",className:"language-json"},'"override": {\n  "build": "dune build"\n}\n')),(0,a.kt)("h3",{id:"install"},(0,a.kt)("inlineCode",{parentName:"h3"},"install")),(0,a.kt)("p",null,"This replaces ",(0,a.kt)("a",{parentName:"p",href:"/docs/configuration#esyinstall"},"esy.install")," commands of the origin\nconfiguration."),(0,a.kt)("pre",null,(0,a.kt)("code",{parentName:"pre",className:"language-json"},'"override": {\n  "install": "esy-installer project.install"\n}\n')),(0,a.kt)("h3",{id:"exportedenv"},(0,a.kt)("inlineCode",{parentName:"h3"},"exportedEnv")),(0,a.kt)("p",null,"This replaces ",(0,a.kt)("a",{parentName:"p",href:"/docs/configuration#esyexportedenv"},"esy.exportedEnv")," set of exported\nenvironment variables of the origin configuration."),(0,a.kt)("pre",null,(0,a.kt)("code",{parentName:"pre",className:"language-json"},'"exportedEnv": {\n  "NAME": {"val": "VALUE", "scope": "global"}\n}\n')),(0,a.kt)("p",null,"If you need to add to a set of exported environment variables rather than\nreplace the whole set use ",(0,a.kt)("inlineCode",{parentName:"p"},"exportedEnvOverride")," key instead."),(0,a.kt)("h3",{id:"exportedenvoverride"},(0,a.kt)("inlineCode",{parentName:"h3"},"exportedEnvOverride")),(0,a.kt)("p",null,"This overrides ",(0,a.kt)("a",{parentName:"p",href:"/docs/configuration#esyexportedenv"},"esy.exportedEnv")," set of exported\nenvironment variables of the origin configuration."),(0,a.kt)("p",null,"Environment variables specified using this key are being added instead of\nreplacing the entire set. If a declaration for an environment variable is set to\n",(0,a.kt)("inlineCode",{parentName:"p"},"null")," then the variable is removed from the set."),(0,a.kt)("pre",null,(0,a.kt)("code",{parentName:"pre",className:"language-json"},'"exportedEnvOverride": {\n  "VAR_TO_ADD": {"val": "VALUE", "scope": "global"},\n  "VAR_TO_REMOVE": null\n}\n')),(0,a.kt)("h3",{id:"buildenv"},(0,a.kt)("inlineCode",{parentName:"h3"},"buildEnv")),(0,a.kt)("p",null,"This replaces ",(0,a.kt)("a",{parentName:"p",href:"/docs/configuration#esybuildenv"},"esy.buildEnv")," set of build\nenvironment variables of the origin configuration."),(0,a.kt)("pre",null,(0,a.kt)("code",{parentName:"pre",className:"language-json"},'"buildEnv": {\n  "NAME": "VALUE"\n}\n')),(0,a.kt)("p",null,"If you need to add to a set of build environment variables rather than\nreplace the whole set use ",(0,a.kt)("inlineCode",{parentName:"p"},"buildEnvOverride")," key instead."),(0,a.kt)("h3",{id:"buildenvoverride"},(0,a.kt)("inlineCode",{parentName:"h3"},"buildEnvOverride")),(0,a.kt)("p",null,"This overrides ",(0,a.kt)("a",{parentName:"p",href:"/docs/configuration#esybuildenv"},"esy.buildEnv")," set of build\nenvironment variables of the origin configuration."),(0,a.kt)("p",null,"Environment variables specified using this key are being added instead of\nreplacing the entire set. If a declaration for an environment variable is set to\n",(0,a.kt)("inlineCode",{parentName:"p"},"null")," then the variable is removed from the set."),(0,a.kt)("pre",null,(0,a.kt)("code",{parentName:"pre",className:"language-json"},'"buildEnvOverride": {\n  "VAR_TO_ADD": "VALUE",\n  "VAR_TO_REMOVE": null\n}\n')),(0,a.kt)("h3",{id:"dependencies"},(0,a.kt)("inlineCode",{parentName:"h3"},"dependencies")),(0,a.kt)("p",null,"This overrides ",(0,a.kt)("a",{parentName:"p",href:"/docs/configuration#dependencies"},"dependencies")," set of dependency\ndeclaraations of the origin configuration."),(0,a.kt)("pre",null,(0,a.kt)("code",{parentName:"pre",className:"language-json"},'"dependencies": {\n  "dependency-to-add": "^1.0.0",\n  "dependency-to-remove": null\n}\n')),(0,a.kt)("h3",{id:"devdependencies"},(0,a.kt)("inlineCode",{parentName:"h3"},"devDependencies")),(0,a.kt)("p",null,"This overrides ",(0,a.kt)("a",{parentName:"p",href:"/docs/configuration#devDependencies"},"devDependencies")," set of dev\ndependencies of the origin configuration."),(0,a.kt)("pre",null,(0,a.kt)("code",{parentName:"pre",className:"language-json"},'"devDependencies": {\n  "dependency-to-add": "^1.0.0",\n  "dependency-to-remove": null\n}\n')),(0,a.kt)("h3",{id:"resolutions"},(0,a.kt)("inlineCode",{parentName:"h3"},"resolutions")),(0,a.kt)("p",null,"This replaces ",(0,a.kt)("a",{parentName:"p",href:"/docs/configuration#resolutions"},"resolutions")," set of dependency\nresolutions."))}u.isMDXComponent=!0}}]);