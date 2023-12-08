"use strict";(self.webpackChunksite_v_3=self.webpackChunksite_v_3||[]).push([[2638],{5871:(e,n,s)=>{s.r(n),s.d(n,{assets:()=>l,contentTitle:()=>r,default:()=>h,frontMatter:()=>o,metadata:()=>a,toc:()=>d});var t=s(5893),i=s(1151);const o={id:"faqs",title:"Frequently Asked Questions"},r=void 0,a={id:"faqs",title:"Frequently Asked Questions",description:"This is a running list of frequently asked questions (recommendations are very welcome)",source:"@site/../docs/faqs.md",sourceDirName:".",slug:"/faqs",permalink:"/docs/faqs",draft:!1,unlisted:!1,editUrl:"https://github.com/esy/esy/tree/master/docs/../docs/faqs.md",tags:[],version:"current",lastUpdatedBy:"prometheansacrifice",lastUpdatedAt:1702029753,formattedLastUpdatedAt:"Dec 8, 2023",frontMatter:{id:"faqs",title:"Frequently Asked Questions"},sidebar:"docs",previous:{title:"Node/npm Compatibility",permalink:"/docs/node-compatibility"},next:{title:"Community",permalink:"/docs/community"}},l={},d=[{value:"Dynamic linking issues with npm release: &quot;Library not loaded /opt/homebrew/.../esy_openssl-93ba2454/lib/libssl.1.1.dylib&quot;",id:"dynamic-linking-issues-with-npm-release-library-not-loaded-opthomebrewesy_openssl-93ba2454liblibssl11dylib",level:2},{value:"Why doesn&#39;t Esy support Dune operations like opam file generation or copying of JS files in the source tree?",id:"why-doesnt-esy-support-dune-operations-like-opam-file-generation-or-copying-of-js-files-in-the-source-tree",level:2},{value:"How to generate opam file with Dune?",id:"how-to-generate-opam-file-with-dune",level:2}];function c(e){const n={a:"a",code:"code",h2:"h2",p:"p",pre:"pre",...(0,i.a)(),...e.components};return(0,t.jsxs)(t.Fragment,{children:[(0,t.jsx)(n.p,{children:"This is a running list of frequently asked questions (recommendations are very welcome)"}),"\n",(0,t.jsx)(n.h2,{id:"dynamic-linking-issues-with-npm-release-library-not-loaded-opthomebrewesy_openssl-93ba2454liblibssl11dylib",children:'Dynamic linking issues with npm release: "Library not loaded /opt/homebrew/.../esy_openssl-93ba2454/lib/libssl.1.1.dylib"'}),"\n",(0,t.jsxs)(n.p,{children:["TLDR; Ensure that required package, in this case ",(0,t.jsx)(n.code,{children:"esy-openssl"}),", in present in ",(0,t.jsx)(n.code,{children:"esy.release.includePackages"})," property of ",(0,t.jsx)(n.code,{children:"esy.json"}),"/",(0,t.jsx)(n.code,{children:"package.json"})]}),"\n",(0,t.jsxs)(n.p,{children:["Binaries often rely on dynamic libraries (esp. on MacOS). HTTP servers relying on popular frameworks to implement https would often rely on openssl, which is often dynamically linked on MacOS (Linux too by default). These need to be present in the sandbox when the binary runs (example, the HTTP server). This happens easily when one runs ",(0,t.jsx)(n.code,{children:"esy x my-http-server.exe"}),". But, when packaged as an npm package, ",(0,t.jsx)(n.code,{children:"esy-openssl"})," must be present in the binary's environment. ",(0,t.jsx)(n.code,{children:"esy"})," already ensures present during ",(0,t.jsx)(n.code,{children:"esy x ..."})," is also present in binaries exported as NPM package. But it doesn't, by default, export all the packages - they have to be opted in as and when needed. To ensure such dynamically linked library packages are included in the environment of the exported NPM packages, use ",(0,t.jsx)(n.code,{children:"includePackages"})," property (as explained ",(0,t.jsx)(n.a,{href:"https://esy.sh/docs/en/npm-release.html#including-dependencies",children:"here"}),")"]}),"\n",(0,t.jsx)(n.pre,{children:(0,t.jsx)(n.code,{className:"language-diff",children:'      "includePackages": [\n        "root",\n        "esy-gmp",\n+       "esy-openssl"\n      ],\n'})}),"\n",(0,t.jsx)(n.h2,{id:"why-doesnt-esy-support-dune-operations-like-opam-file-generation-or-copying-of-js-files-in-the-source-tree",children:"Why doesn't Esy support Dune operations like opam file generation or copying of JS files in the source tree?"}),"\n",(0,t.jsxs)(n.p,{children:["TLDR; If you're looking to generate opam files with Dune, use ",(0,t.jsx)(n.code,{children:"esy dune build <project opam file>"}),". For substitution, use ",(0,t.jsx)(n.code,{children:"esy dune substs"}),"."]}),"\n",(0,t.jsxs)(n.p,{children:["Any build operation is recommended to be run in an isolated sandboxed environment where the sources are considered\nimmutable. Esy uses sandbox-exec on MacOS to enforce a sandbox (Linux and Windows are pending). It is always recommended\nthat build commands are run with ",(0,t.jsx)(n.code,{children:"esy b ..."})," prefix. For this to work, esy assumes that there is no inplace editing of the\nsource tree - any in-place editing of sources that take place in the isolated phase makes it hard for esy to bet on immutability\nand hence it is not written to handle it well at the moment (hence the cryptic error messages)"]}),"\n",(0,t.jsxs)(n.p,{children:["Any command that does not generate build artifacts (dune subst, launching lightweight editors etc) are recommended to be run with\njust ",(0,t.jsx)(n.code,{children:"esy ..."})," prefix (We call it the ",(0,t.jsx)(n.a,{href:"https://esy.sh/docs/en/environment.html#command-environment",children:"command environment"})," to distinguish it from ",(0,t.jsx)(n.a,{href:"https://esy.sh/docs/en/environment.html#build-environment",children:"build environment"}),")"]}),"\n",(0,t.jsx)(n.p,{children:"Esy prefers immutability of sources and built artifacts so that it can provide reproducibility guarantees and other benefits immutability brings."}),"\n",(0,t.jsx)(n.h2,{id:"how-to-generate-opam-file-with-dune",children:"How to generate opam file with Dune?"}),"\n",(0,t.jsx)(n.p,{children:(0,t.jsx)(n.code,{children:"esy dune build hello-reason.opam"})}),"\n",(0,t.jsxs)(n.p,{children:["It seems there is no way to generate opam files only in the build directory.\n",(0,t.jsx)(n.a,{href:"https://discord.com/channels/436568060288172042/469167238268715021/718879610804371506",children:"https://discord.com/channels/436568060288172042/469167238268715021/718879610804371506"})]}),"\n",(0,t.jsx)(n.p,{children:"This means dune build hello-reason.opam will not treat the source tree as immutable."})]})}function h(e={}){const{wrapper:n}={...(0,i.a)(),...e.components};return n?(0,t.jsx)(n,{...e,children:(0,t.jsx)(c,{...e})}):c(e)}},1151:(e,n,s)=>{s.d(n,{Z:()=>a,a:()=>r});var t=s(7294);const i={},o=t.createContext(i);function r(e){const n=t.useContext(o);return t.useMemo((function(){return"function"==typeof e?e(n):{...n,...e}}),[n,e])}function a(e){let n;return n=e.disableParentContext?"function"==typeof e.components?e.components(i):e.components||i:r(e.components),t.createElement(o.Provider,{value:n},e.children)}}}]);