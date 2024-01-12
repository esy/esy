"use strict";(self.webpackChunksite_v_3=self.webpackChunksite_v_3||[]).push([[9622],{5289:(e,n,t)=>{t.r(n),t.d(n,{assets:()=>l,contentTitle:()=>r,default:()=>h,frontMatter:()=>o,metadata:()=>c,toc:()=>d});var s=t(5893),i=t(1151);const o={id:"ci",title:"Notes about CI/CD"},r=void 0,c={id:"contributing/ci",title:"Notes about CI/CD",description:"We use Azure Pipelines for",source:"@site/../docs/contributing/ci.md",sourceDirName:"contributing",slug:"/contributing/ci",permalink:"/docs/contributing/ci",draft:!1,unlisted:!1,editUrl:"https://github.com/esy/esy/tree/master/docs/../docs/contributing/ci.md",tags:[],version:"current",lastUpdatedBy:"prometheansacrifice",lastUpdatedAt:1705048059,formattedLastUpdatedAt:"Jan 12, 2024",frontMatter:{id:"ci",title:"Notes about CI/CD"},sidebar:"docs",previous:{title:"Website and documentation",permalink:"/docs/contributing/website-and-docs"},next:{title:"Release Process",permalink:"/docs/contributing/release-process"}},l={},d=[{value:"What is EsyVersion.re?",id:"what-is-esyversionre",level:3}];function a(e){const n={a:"a",code:"code",h3:"h3",li:"li",ol:"ol",p:"p",pre:"pre",...(0,i.a)(),...e.components};return(0,s.jsxs)(s.Fragment,{children:[(0,s.jsxs)(n.p,{children:["We use ",(0,s.jsx)(n.a,{href:"https://dev.azure.com/esy-dev/esy/_build",children:"Azure Pipelines"})," for\nCI/CD. Every successful build from ",(0,s.jsx)(n.code,{children:"master"})," branch is automatically\npublished to NPM under ",(0,s.jsx)(n.code,{children:"@esy-nightly/esy"})," name. We could,"]}),"\n",(0,s.jsxs)(n.ol,{children:["\n",(0,s.jsx)(n.li,{children:"Download the artifact directly from Azure Pipelines, or"}),"\n",(0,s.jsx)(n.li,{children:"Download the nightly npm tarball."}),"\n"]}),"\n",(0,s.jsx)(n.h3,{id:"what-is-esyversionre",children:"What is EsyVersion.re?"}),"\n",(0,s.jsxs)(n.p,{children:["We infer esy version with git. A script, ",(0,s.jsx)(n.code,{children:"version.sh"})," is present in\n",(0,s.jsx)(n.code,{children:"esy-version/"}),". This script can output a ",(0,s.jsx)(n.code,{children:"let"})," statement in OCaml or\nReason containing the version."]}),"\n",(0,s.jsx)(n.pre,{children:(0,s.jsx)(n.code,{className:"language-sh",children:"sh ./esy-version/version.sh --reason\n"})}),"\n",(0,s.jsxs)(n.p,{children:["Internally, it uses ",(0,s.jsx)(n.code,{children:"git describe --tags"})]}),"\n",(0,s.jsxs)(n.p,{children:["During development, it's not absolutely necessary to run this script\nbecause ",(0,s.jsx)(n.code,{children:".git/"})," is always present and Dune is configured extract\nit. This, however, is not true for CI as we develop for different\nplatforms/distribution channels. Case in point, Nix and Docker. Even,\n",(0,s.jsx)(n.code,{children:"esy release"})," copies the source tree (without ",(0,s.jsx)(n.code,{children:".git/"}),") in isolation to\nprepare the npm tarball."]}),"\n",(0,s.jsxs)(n.p,{children:["Therefore, on the CI, it's necessary to generate ",(0,s.jsx)(n.code,{children:"EsyVersion.re"})," file\ncontaining the version with the ",(0,s.jsx)(n.code,{children:"version.sh"})," script before running\nany of the build commands. You can see this in ",(0,s.jsx)(n.code,{children:"build-platform.yml"}),"\nright after the ",(0,s.jsx)(n.code,{children:"git clone"})," job."]}),"\n",(0,s.jsxs)(n.p,{children:["Note: you'll need the CI to fetch tags as it clones. By default, for\ninstance, Github Actions only shallow clones the repository, which\ndoes not fetch tags. Fetching ",(0,s.jsx)(n.code,{children:"n"})," number of commits during the shallow\nclone isn't helpful either. This is why, ",(0,s.jsx)(n.code,{children:"fetch-depth"})," is set to ",(0,s.jsx)(n.code,{children:"0"}),"\nin the Nix Github Actions workflow. (",(0,s.jsx)(n.code,{children:"nix.yml"}),")"]})]})}function h(e={}){const{wrapper:n}={...(0,i.a)(),...e.components};return n?(0,s.jsx)(n,{...e,children:(0,s.jsx)(a,{...e})}):a(e)}},1151:(e,n,t)=>{t.d(n,{Z:()=>c,a:()=>r});var s=t(7294);const i={},o=s.createContext(i);function r(e){const n=s.useContext(o);return s.useMemo((function(){return"function"==typeof e?e(n):{...n,...e}}),[n,e])}function c(e){let n;return n=e.disableParentContext?"function"==typeof e.components?e.components(i):e.components||i:r(e.components),s.createElement(o.Provider,{value:n},e.children)}}}]);