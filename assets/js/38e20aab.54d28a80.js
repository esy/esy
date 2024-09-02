"use strict";(self.webpackChunksite_v_3=self.webpackChunksite_v_3||[]).push([[8703],{5617:(e,n,s)=>{s.r(n),s.d(n,{assets:()=>t,contentTitle:()=>r,default:()=>p,frontMatter:()=>l,metadata:()=>o,toc:()=>c});var i=s(5893),a=s(1151);const l={id:"what-why",title:"What & Why"},r=void 0,o={id:"what-why",title:"What & Why",description:"esy is a rapid workflow for developing Reason/OCaml projects. It supports native",source:"@site/../docs/what-why.md",sourceDirName:".",slug:"/what-why",permalink:"/docs/what-why",draft:!1,unlisted:!1,editUrl:"https://github.com/esy/esy/tree/master/docs/../docs/what-why.md",tags:[],version:"current",lastUpdatedBy:"prometheansacrifice",lastUpdatedAt:1725276666,formattedLastUpdatedAt:"Sep 2, 2024",frontMatter:{id:"what-why",title:"What & Why"},sidebar:"docs",next:{title:"Getting started",permalink:"/docs/getting-started"}},t={},c=[{value:"For npm users",id:"for-npm-users",level:2},{value:"For opam users",id:"for-opam-users",level:2},{value:"In depth",id:"in-depth",level:2}];function d(e){const n={a:"a",code:"code",h2:"h2",li:"li",p:"p",ul:"ul",...(0,a.a)(),...e.components};return(0,i.jsxs)(i.Fragment,{children:[(0,i.jsx)(n.p,{children:"esy is a rapid workflow for developing Reason/OCaml projects. It supports native\npackages hosted on opam and npm."}),"\n",(0,i.jsxs)(n.h2,{id:"for-npm-users",children:["For ",(0,i.jsx)(n.a,{href:"https://npmjs.org/",children:"npm"})," users"]}),"\n",(0,i.jsx)(n.p,{children:"esy lets you manage native Reason/OCaml projects with a familiar npm-like workflow:"}),"\n",(0,i.jsxs)(n.ul,{children:["\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsxs)(n.p,{children:["Declare dependencies in ",(0,i.jsx)(n.code,{children:"package.json"}),"."]}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsxs)(n.p,{children:["Run the ",(0,i.jsx)(n.code,{children:"esy"})," command within your project to download/build dependencies."]}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsx)(n.p,{children:"Share and consume individual Reason/OCaml package sources on the npm registry or Github."}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsxs)(n.p,{children:["Access packages published on ",(0,i.jsx)(n.a,{href:"https://opam.ocaml.org/",children:"opam"})," (a package\nregistry for OCaml) via ",(0,i.jsx)(n.code,{children:"@opam"})," npm scope (for example ",(0,i.jsx)(n.code,{children:"@opam/lwt"})," to pull\n",(0,i.jsx)(n.code,{children:"lwt"})," library from opam)."]}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsx)(n.p,{children:"Easily bundle your project into a self contained, prebuilt binary package and share it\non npm. These can be installed by anyone using plain npm."}),"\n"]}),"\n"]}),"\n",(0,i.jsxs)(n.h2,{id:"for-opam-users",children:["For ",(0,i.jsx)(n.a,{href:"https://opam.ocaml.org/",children:"opam"})," users"]}),"\n",(0,i.jsx)(n.p,{children:'esy provides a fast and powerful workflow for local development of opam packages without\nrequiring "switches". Opam packages are still accessible, and you can publish\nyour packages to opam repository.'}),"\n",(0,i.jsxs)(n.ul,{children:["\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsx)(n.p,{children:"Manages OCaml compilers and dependencies on a per project basis."}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsx)(n.p,{children:"Isolates each package environment by exposing only those packages which are\ndefined as dependencies."}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsx)(n.p,{children:"Fast parallel builds which are aggressively cached (even across different\nprojects)."}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsx)(n.p,{children:"Keeps the ability to use packages published on opam repository."}),"\n"]}),"\n"]}),"\n",(0,i.jsx)(n.h2,{id:"in-depth",children:"In depth"}),"\n",(0,i.jsxs)(n.ul,{children:["\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsxs)(n.p,{children:["Project metadata is managed inside ",(0,i.jsx)(n.code,{children:"package.json"}),"."]}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsx)(n.p,{children:"Parallel builds."}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsx)(n.p,{children:"Clean environment builds for reproducibility."}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsx)(n.p,{children:"Global build cache automatically shared across all projects \u2014 initializing new\nprojects is often cheap."}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsx)(n.p,{children:"File system checks to prevent builds from mutating locations they don't\nown."}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsxs)(n.p,{children:["Solves environment variable pain. Native toolchains rely heavily on environment\nvariables, and ",(0,i.jsx)(n.code,{children:"esy"})," makes them behave predictably, and usually even gets them\nout of your way entirely."]}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsxs)(n.p,{children:["Allows symlink style workflows for local development using ",(0,i.jsx)(n.code,{children:"link:"}),' dependencies.\nAllows you to work on several projects locally, automatically rebuilding any\nlinked dependencies that have changed. There is no need to first register a package\nas "linkable".']}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsxs)(n.p,{children:["Run commands in project environment quickly ",(0,i.jsx)(n.code,{children:"esy <anycommand>"}),"."]}),"\n"]}),"\n"]})]})}function p(e={}){const{wrapper:n}={...(0,a.a)(),...e.components};return n?(0,i.jsx)(n,{...e,children:(0,i.jsx)(d,{...e})}):d(e)}},1151:(e,n,s)=>{s.d(n,{Z:()=>o,a:()=>r});var i=s(7294);const a={},l=i.createContext(a);function r(e){const n=i.useContext(l);return i.useMemo((function(){return"function"==typeof e?e(n):{...n,...e}}),[n,e])}function o(e){let n;return n=e.disableParentContext?"function"==typeof e.components?e.components(a):e.components||a:r(e.components),i.createElement(l.Provider,{value:n},e.children)}}}]);