"use strict";(self.webpackChunksite_v_3=self.webpackChunksite_v_3||[]).push([[2638],{3905:(e,n,t)=>{t.d(n,{Zo:()=>d,kt:()=>y});var r=t(7294);function i(e,n,t){return n in e?Object.defineProperty(e,n,{value:t,enumerable:!0,configurable:!0,writable:!0}):e[n]=t,e}function o(e,n){var t=Object.keys(e);if(Object.getOwnPropertySymbols){var r=Object.getOwnPropertySymbols(e);n&&(r=r.filter((function(n){return Object.getOwnPropertyDescriptor(e,n).enumerable}))),t.push.apply(t,r)}return t}function a(e){for(var n=1;n<arguments.length;n++){var t=null!=arguments[n]?arguments[n]:{};n%2?o(Object(t),!0).forEach((function(n){i(e,n,t[n])})):Object.getOwnPropertyDescriptors?Object.defineProperties(e,Object.getOwnPropertyDescriptors(t)):o(Object(t)).forEach((function(n){Object.defineProperty(e,n,Object.getOwnPropertyDescriptor(t,n))}))}return e}function s(e,n){if(null==e)return{};var t,r,i=function(e,n){if(null==e)return{};var t,r,i={},o=Object.keys(e);for(r=0;r<o.length;r++)t=o[r],n.indexOf(t)>=0||(i[t]=e[t]);return i}(e,n);if(Object.getOwnPropertySymbols){var o=Object.getOwnPropertySymbols(e);for(r=0;r<o.length;r++)t=o[r],n.indexOf(t)>=0||Object.prototype.propertyIsEnumerable.call(e,t)&&(i[t]=e[t])}return i}var l=r.createContext({}),p=function(e){var n=r.useContext(l),t=n;return e&&(t="function"==typeof e?e(n):a(a({},n),e)),t},d=function(e){var n=p(e.components);return r.createElement(l.Provider,{value:n},e.children)},u="mdxType",c={inlineCode:"code",wrapper:function(e){var n=e.children;return r.createElement(r.Fragment,{},n)}},m=r.forwardRef((function(e,n){var t=e.components,i=e.mdxType,o=e.originalType,l=e.parentName,d=s(e,["components","mdxType","originalType","parentName"]),u=p(t),m=i,y=u["".concat(l,".").concat(m)]||u[m]||c[m]||o;return t?r.createElement(y,a(a({ref:n},d),{},{components:t})):r.createElement(y,a({ref:n},d))}));function y(e,n){var t=arguments,i=n&&n.mdxType;if("string"==typeof e||i){var o=t.length,a=new Array(o);a[0]=m;var s={};for(var l in n)hasOwnProperty.call(n,l)&&(s[l]=n[l]);s.originalType=e,s[u]="string"==typeof e?e:i,a[1]=s;for(var p=2;p<o;p++)a[p]=t[p];return r.createElement.apply(null,a)}return r.createElement.apply(null,t)}m.displayName="MDXCreateElement"},3048:(e,n,t)=>{t.r(n),t.d(n,{assets:()=>l,contentTitle:()=>a,default:()=>c,frontMatter:()=>o,metadata:()=>s,toc:()=>p});var r=t(7462),i=(t(7294),t(3905));const o={id:"faqs",title:"Frequently Asked Questions"},a=void 0,s={unversionedId:"faqs",id:"faqs",title:"Frequently Asked Questions",description:"This is a running list of frequently asked questions (recommendations are very welcome)",source:"@site/../docs/faqs.md",sourceDirName:".",slug:"/faqs",permalink:"/docs/faqs",draft:!1,editUrl:"https://github.com/esy/esy/tree/master/docs/../docs/faqs.md",tags:[],version:"current",lastUpdatedBy:"dependabot[bot]",lastUpdatedAt:1697771738,formattedLastUpdatedAt:"Oct 20, 2023",frontMatter:{id:"faqs",title:"Frequently Asked Questions"},sidebar:"docs",previous:{title:"Node/npm Compatibility",permalink:"/docs/node-compatibility"},next:{title:"Community",permalink:"/docs/community"}},l={},p=[{value:"Dynamic linking issues with npm release: &quot;Library not loaded /opt/homebrew/.../esy_openssl-93ba2454/lib/libssl.1.1.dylib&quot;",id:"dynamic-linking-issues-with-npm-release-library-not-loaded-opthomebrewesy_openssl-93ba2454liblibssl11dylib",level:2},{value:"Why doesn&#39;t Esy support Dune operations like opam file generation or copying of JS files in the source tree?",id:"why-doesnt-esy-support-dune-operations-like-opam-file-generation-or-copying-of-js-files-in-the-source-tree",level:2},{value:"How to generate opam file with Dune?",id:"how-to-generate-opam-file-with-dune",level:2}],d={toc:p},u="wrapper";function c(e){let{components:n,...t}=e;return(0,i.kt)(u,(0,r.Z)({},d,t,{components:n,mdxType:"MDXLayout"}),(0,i.kt)("p",null,"This is a running list of frequently asked questions (recommendations are very welcome)"),(0,i.kt)("h2",{id:"dynamic-linking-issues-with-npm-release-library-not-loaded-opthomebrewesy_openssl-93ba2454liblibssl11dylib"},'Dynamic linking issues with npm release: "Library not loaded /opt/homebrew/.../esy_openssl-93ba2454/lib/libssl.1.1.dylib"'),(0,i.kt)("p",null,"TLDR; Ensure that required package, in this case ",(0,i.kt)("inlineCode",{parentName:"p"},"esy-openssl"),", in present in ",(0,i.kt)("inlineCode",{parentName:"p"},"esy.release.includePackages")," property of ",(0,i.kt)("inlineCode",{parentName:"p"},"esy.json"),"/",(0,i.kt)("inlineCode",{parentName:"p"},"package.json")),(0,i.kt)("p",null,"Binaries often rely on dynamic libraries (esp. on MacOS). HTTP servers relying on popular frameworks to implement https would often rely on openssl, which is often dynamically linked on MacOS (Linux too by default). These need to be present in the sandbox when the binary runs (example, the HTTP server). This happens easily when one runs ",(0,i.kt)("inlineCode",{parentName:"p"},"esy x my-http-server.exe"),". But, when packaged as an npm package, ",(0,i.kt)("inlineCode",{parentName:"p"},"esy-openssl")," must be present in the binary's environment. ",(0,i.kt)("inlineCode",{parentName:"p"},"esy")," already ensures present during ",(0,i.kt)("inlineCode",{parentName:"p"},"esy x ...")," is also present in binaries exported as NPM package. But it doesn't, by default, export all the packages - they have to be opted in as and when needed. To ensure such dynamically linked library packages are included in the environment of the exported NPM packages, use ",(0,i.kt)("inlineCode",{parentName:"p"},"includePackages")," property (as explained ",(0,i.kt)("a",{parentName:"p",href:"https://esy.sh/docs/en/npm-release.html#including-dependencies"},"here"),")"),(0,i.kt)("pre",null,(0,i.kt)("code",{parentName:"pre",className:"language-diff"},'      "includePackages": [\n        "root",\n        "esy-gmp",\n+       "esy-openssl"\n      ],\n')),(0,i.kt)("h2",{id:"why-doesnt-esy-support-dune-operations-like-opam-file-generation-or-copying-of-js-files-in-the-source-tree"},"Why doesn't Esy support Dune operations like opam file generation or copying of JS files in the source tree?"),(0,i.kt)("p",null,"TLDR; If you're looking to generate opam files with Dune, use ",(0,i.kt)("inlineCode",{parentName:"p"},"esy dune build <project opam file>"),". For substitution, use ",(0,i.kt)("inlineCode",{parentName:"p"},"esy dune substs"),"."),(0,i.kt)("p",null,"Any build operation is recommended to be run in an isolated sandboxed environment where the sources are considered\nimmutable. Esy uses sandbox-exec on MacOS to enforce a sandbox (Linux and Windows are pending). It is always recommended\nthat build commands are run with ",(0,i.kt)("inlineCode",{parentName:"p"},"esy b ...")," prefix. For this to work, esy assumes that there is no inplace editing of the\nsource tree - any in-place editing of sources that take place in the isolated phase makes it hard for esy to bet on immutability\nand hence it is not written to handle it well at the moment (hence the cryptic error messages)"),(0,i.kt)("p",null,"Any command that does not generate build artifacts (dune subst, launching lightweight editors etc) are recommended to be run with\njust ",(0,i.kt)("inlineCode",{parentName:"p"},"esy ...")," prefix (We call it the ",(0,i.kt)("a",{parentName:"p",href:"https://esy.sh/docs/en/environment.html#command-environment"},"command environment")," to distinguish it from ",(0,i.kt)("a",{parentName:"p",href:"https://esy.sh/docs/en/environment.html#build-environment"},"build environment"),")"),(0,i.kt)("p",null,"Esy prefers immutability of sources and built artifacts so that it can provide reproducibility guarantees and other benefits immutability brings."),(0,i.kt)("h2",{id:"how-to-generate-opam-file-with-dune"},"How to generate opam file with Dune?"),(0,i.kt)("p",null,(0,i.kt)("inlineCode",{parentName:"p"},"esy dune build hello-reason.opam")),(0,i.kt)("p",null,"It seems there is no way to generate opam files only in the build directory.\n",(0,i.kt)("a",{parentName:"p",href:"https://discord.com/channels/436568060288172042/469167238268715021/718879610804371506"},"https://discord.com/channels/436568060288172042/469167238268715021/718879610804371506")),(0,i.kt)("p",null,"This means dune build hello-reason.opam will not treat the source tree as immutable."))}c.isMDXComponent=!0}}]);