"use strict";(self.webpackChunksite_v_3=self.webpackChunksite_v_3||[]).push([[6462],{3905:(e,t,n)=>{n.d(t,{Zo:()=>d,kt:()=>h});var i=n(7294);function r(e,t,n){return t in e?Object.defineProperty(e,t,{value:n,enumerable:!0,configurable:!0,writable:!0}):e[t]=n,e}function a(e,t){var n=Object.keys(e);if(Object.getOwnPropertySymbols){var i=Object.getOwnPropertySymbols(e);t&&(i=i.filter((function(t){return Object.getOwnPropertyDescriptor(e,t).enumerable}))),n.push.apply(n,i)}return n}function l(e){for(var t=1;t<arguments.length;t++){var n=null!=arguments[t]?arguments[t]:{};t%2?a(Object(n),!0).forEach((function(t){r(e,t,n[t])})):Object.getOwnPropertyDescriptors?Object.defineProperties(e,Object.getOwnPropertyDescriptors(n)):a(Object(n)).forEach((function(t){Object.defineProperty(e,t,Object.getOwnPropertyDescriptor(n,t))}))}return e}function s(e,t){if(null==e)return{};var n,i,r=function(e,t){if(null==e)return{};var n,i,r={},a=Object.keys(e);for(i=0;i<a.length;i++)n=a[i],t.indexOf(n)>=0||(r[n]=e[n]);return r}(e,t);if(Object.getOwnPropertySymbols){var a=Object.getOwnPropertySymbols(e);for(i=0;i<a.length;i++)n=a[i],t.indexOf(n)>=0||Object.prototype.propertyIsEnumerable.call(e,n)&&(r[n]=e[n])}return r}var o=i.createContext({}),p=function(e){var t=i.useContext(o),n=t;return e&&(n="function"==typeof e?e(t):l(l({},t),e)),n},d=function(e){var t=p(e.components);return i.createElement(o.Provider,{value:t},e.children)},u="mdxType",c={inlineCode:"code",wrapper:function(e){var t=e.children;return i.createElement(i.Fragment,{},t)}},m=i.forwardRef((function(e,t){var n=e.components,r=e.mdxType,a=e.originalType,o=e.parentName,d=s(e,["components","mdxType","originalType","parentName"]),u=p(n),m=r,h=u["".concat(o,".").concat(m)]||u[m]||c[m]||a;return n?i.createElement(h,l(l({ref:t},d),{},{components:n})):i.createElement(h,l({ref:t},d))}));function h(e,t){var n=arguments,r=t&&t.mdxType;if("string"==typeof e||r){var a=n.length,l=new Array(a);l[0]=m;var s={};for(var o in t)hasOwnProperty.call(t,o)&&(s[o]=t[o]);s.originalType=e,s[u]="string"==typeof e?e:r,l[1]=s;for(var p=2;p<a;p++)l[p]=n[p];return i.createElement.apply(null,l)}return i.createElement.apply(null,n)}m.displayName="MDXCreateElement"},4451:(e,t,n)=>{n.r(t),n.d(t,{assets:()=>o,contentTitle:()=>l,default:()=>c,frontMatter:()=>a,metadata:()=>s,toc:()=>p});var i=n(7462),r=(n(7294),n(3905));const a={id:"development",title:"Development"},l=void 0,s={unversionedId:"development",id:"development",title:"Development",description:"To make changes to esy and test them locally:",source:"@site/../docs/development.md",sourceDirName:".",slug:"/development",permalink:"/docs/development",draft:!1,editUrl:"https://github.com/esy/esy/tree/master/docs/../docs/development.md",tags:[],version:"current",lastUpdatedBy:"Manas",lastUpdatedAt:1693535474,formattedLastUpdatedAt:"Sep 1, 2023",frontMatter:{id:"development",title:"Development"},sidebar:"docs",previous:{title:"How esy works",permalink:"/docs/how-it-works"}},o={},p=[{value:"Running Tests",id:"running-tests",level:2},{value:"Issues",id:"issues",level:2},{value:"Publishing Releases",id:"publishing-releases",level:2},{value:"CI",id:"ci",level:2},{value:"EsyVersion.re",id:"esyversionre",level:3}],d={toc:p},u="wrapper";function c(e){let{components:t,...n}=e;return(0,r.kt)(u,(0,i.Z)({},d,n,{components:t,mdxType:"MDXLayout"}),(0,r.kt)("p",null,"To make changes to ",(0,r.kt)("inlineCode",{parentName:"p"},"esy")," and test them locally:"),(0,r.kt)("pre",null,(0,r.kt)("code",{parentName:"pre",className:"language-bash"},"git clone git://github.com/esy/esy.git\ncd esy\n")),(0,r.kt)("p",null,"And then,"),(0,r.kt)("p",null,"On Linux/MacOS, run newly built ",(0,r.kt)("inlineCode",{parentName:"p"},"esy")," executable from anywhere like ",(0,r.kt)("inlineCode",{parentName:"p"},"PATH_TO_REPO/_build/default/bin/esy"),".\nOn Windows, use the cmd wrapper in ",(0,r.kt)("inlineCode",{parentName:"p"},"PATH_TO_REPO/bin/esy.cmd"),". On Windows, esy binary needs ",(0,r.kt)("a",{parentName:"p",href:"https://github.com/esy/esy-bash"},(0,r.kt)("inlineCode",{parentName:"a"},"esy-bash")),". ",(0,r.kt)("inlineCode",{parentName:"p"},"esy")," distributed on NPM finds it in the node_modules, but the dev binary finds it via the ",(0,r.kt)("inlineCode",{parentName:"p"},"ESY__ESY_BASH")," variable in the environment."),(0,r.kt)("h2",{id:"running-tests"},"Running Tests"),(0,r.kt)("ol",null,(0,r.kt)("li",{parentName:"ol"},"Fast tests (no internet connection needed)")),(0,r.kt)("pre",null,(0,r.kt)("code",{parentName:"pre",className:"language-sh"},"yarn jest\n")),(0,r.kt)("ol",{start:2},(0,r.kt)("li",{parentName:"ol"},"Slow tests (needs internet connection)")),(0,r.kt)("pre",null,(0,r.kt)("code",{parentName:"pre",className:"language-sh"},"node ./test-e2e-slow/run-slow-tests.js\n")),(0,r.kt)("ol",{start:3},(0,r.kt)("li",{parentName:"ol"},"Unit tests")),(0,r.kt)("pre",null,(0,r.kt)("code",{parentName:"pre",className:"language-sh"},"esy b dune runtest\n")),(0,r.kt)("h2",{id:"issues"},"Issues"),(0,r.kt)("p",null,"Issues are tracked at ",(0,r.kt)("a",{parentName:"p",href:"https://github.com/esy/esy"},"esy/esy"),"."),(0,r.kt)("h2",{id:"publishing-releases"},"Publishing Releases"),(0,r.kt)("p",null,(0,r.kt)("inlineCode",{parentName:"p"},"esy")," is primarily distributed via NPM (in fact, at the moment, this\nis the only distribution channel). To create an NPM tarball, one could\nsimply run, "),(0,r.kt)("pre",null,(0,r.kt)("code",{parentName:"pre",className:"language-sh"},"esy release\n")),(0,r.kt)("p",null,"And the ",(0,r.kt)("inlineCode",{parentName:"p"},"_release")," folder is ready to be installed via NPM. But since\nit would contain only one platform's binaries (the machine on which it\nwas built), we combine builds from multiple platforms on the CI."),(0,r.kt)("p",null,"We use ",(0,r.kt)("a",{parentName:"p",href:"https://dev.azure.com/esy-dev/esy/_build"},"Azure Pipelines")," for\nCI/CD. Every successful build from ",(0,r.kt)("inlineCode",{parentName:"p"},"master")," branch is automatically\npublished to NPM under ",(0,r.kt)("inlineCode",{parentName:"p"},"@esy-nightly/esy")," name. We could,"),(0,r.kt)("ol",null,(0,r.kt)("li",{parentName:"ol"},"Download the artifact directly from Azure Pipelines, or"),(0,r.kt)("li",{parentName:"ol"},"Download the nightly npm tarball.")),(0,r.kt)("p",null,"Once downloaded, one can update the name and version field according\nto the release."),(0,r.kt)("p",null,"Note, that MacOS M1 isn't available on Azure Pipelines yet. So, this\nbuild is included by building it locally, and placing the ",(0,r.kt)("inlineCode",{parentName:"p"},"_release"),"\nin the ",(0,r.kt)("inlineCode",{parentName:"p"},"platform-darwin-arm64")," folder along side other platforms."),(0,r.kt)("p",null,"Release tag ",(0,r.kt)("inlineCode",{parentName:"p"},"next")," is used to publish preview releases."),(0,r.kt)("h2",{id:"ci"},"CI"),(0,r.kt)("h3",{id:"esyversionre"},"EsyVersion.re"),(0,r.kt)("p",null,"We infer esy version with git. A script, ",(0,r.kt)("inlineCode",{parentName:"p"},"version.sh")," is present in\n",(0,r.kt)("inlineCode",{parentName:"p"},"esy-version/"),". This script can output a ",(0,r.kt)("inlineCode",{parentName:"p"},"let")," statement in OCaml or\nReason containing the version."),(0,r.kt)("pre",null,(0,r.kt)("code",{parentName:"pre",className:"language-sh"},"sh ./esy-version/version.sh --reason\n")),(0,r.kt)("p",null,"Internally, it uses ",(0,r.kt)("inlineCode",{parentName:"p"},"git describe --tags")),(0,r.kt)("p",null,"During development, it's not absolutely necessary to run this script\nbecause ",(0,r.kt)("inlineCode",{parentName:"p"},".git/")," is always present and Dune is configured extract\nit. This, however, is not true for CI as we develop for different\nplatforms/distribution channels. Case in point, Nix and Docker. Even,\n",(0,r.kt)("inlineCode",{parentName:"p"},"esy release")," copies the source tree (without ",(0,r.kt)("inlineCode",{parentName:"p"},".git/"),") in isolation to\nprepare the npm tarball."),(0,r.kt)("p",null,"Therefore, on the CI, it's necessary to generate ",(0,r.kt)("inlineCode",{parentName:"p"},"EsyVersion.re")," file\ncontaining the version with the ",(0,r.kt)("inlineCode",{parentName:"p"},"version.sh")," script before running\nany of the build commands. You can see this in ",(0,r.kt)("inlineCode",{parentName:"p"},"build-platform.yml"),"\nright after the ",(0,r.kt)("inlineCode",{parentName:"p"},"git clone")," job."),(0,r.kt)("p",null,"Note: you'll need the CI to fetch tags as it clones. By default, for\ninstance, Github Actions only shallow clones the repository, which\ndoes not fetch tags. Fetching ",(0,r.kt)("inlineCode",{parentName:"p"},"n")," number of commits during the shallow\nclone isn't helpful either. This is why, ",(0,r.kt)("inlineCode",{parentName:"p"},"fetch-depth")," is set to ",(0,r.kt)("inlineCode",{parentName:"p"},"0"),"\nin the Nix Github Actions workflow. (",(0,r.kt)("inlineCode",{parentName:"p"},"nix.yml"),")"))}c.isMDXComponent=!0}}]);