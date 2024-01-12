"use strict";(self.webpackChunksite_v_3=self.webpackChunksite_v_3||[]).push([[1099],{2210:(e,n,s)=>{s.r(n),s.d(n,{assets:()=>l,contentTitle:()=>d,default:()=>h,frontMatter:()=>r,metadata:()=>o,toc:()=>c});var t=s(5893),i=s(1151);const r={id:"running-tests",title:"Running Tests"},d=void 0,o={id:"contributing/running-tests",title:"Running Tests",description:"esy has primarily 3 kinds of tests.",source:"@site/../docs/contributing/running-tests.md",sourceDirName:"contributing",slug:"/contributing/running-tests",permalink:"/docs/contributing/running-tests",draft:!1,unlisted:!1,editUrl:"https://github.com/esy/esy/tree/master/docs/../docs/contributing/running-tests.md",tags:[],version:"current",lastUpdatedBy:"prometheansacrifice",lastUpdatedAt:1705048059,formattedLastUpdatedAt:"Jan 12, 2024",frontMatter:{id:"running-tests",title:"Running Tests"},sidebar:"docs",previous:{title:"Repository Structure",permalink:"/docs/contributing/repository-structure"},next:{title:"Website and documentation",permalink:"/docs/contributing/website-and-docs"}},l={},c=[{value:"Unit Tests",id:"unit-tests",level:2},{value:"Fast end-to-end tests",id:"fast-end-to-end-tests",level:2},{value:"Slow end-to-end tests",id:"slow-end-to-end-tests",level:2},{value:"Windows",id:"windows",level:2}];function a(e){const n={code:"code",h2:"h2",li:"li",ol:"ol",p:"p",pre:"pre",...(0,i.a)(),...e.components};return(0,t.jsxs)(t.Fragment,{children:[(0,t.jsxs)(n.p,{children:[(0,t.jsx)(n.code,{children:"esy"})," has primarily 3 kinds of tests."]}),"\n",(0,t.jsxs)(n.ol,{children:["\n",(0,t.jsx)(n.li,{children:"Unit tests - useful when developing parsers etc"}),"\n",(0,t.jsx)(n.li,{children:"Slow end-to-end tests"}),"\n",(0,t.jsx)(n.li,{children:"Fast end-to-end tests"}),"\n"]}),"\n",(0,t.jsx)(n.h2,{id:"unit-tests",children:"Unit Tests"}),"\n",(0,t.jsxs)(n.p,{children:["These are present inline in the ",(0,t.jsx)(n.code,{children:"*.re"})," files. To run them,"]}),"\n",(0,t.jsx)(n.pre,{children:(0,t.jsx)(n.code,{children:"esy b dune runtest\n"})}),"\n",(0,t.jsx)(n.h2,{id:"fast-end-to-end-tests",children:"Fast end-to-end tests"}),"\n",(0,t.jsxs)(n.p,{children:["These are present in ",(0,t.jsx)(n.code,{children:"test-e2e"})," folder and are written in JS. They're run by ",(0,t.jsx)(n.code,{children:"jest"})]}),"\n",(0,t.jsx)(n.pre,{children:(0,t.jsx)(n.code,{children:"yarn jest\n"})}),"\n",(0,t.jsx)(n.h2,{id:"slow-end-to-end-tests",children:"Slow end-to-end tests"}),"\n",(0,t.jsxs)(n.p,{children:["They're present in ",(0,t.jsx)(n.code,{children:"test-e2e-slow"})," and are written in JS. They're supposed to mimick the user's workflow\nas closely as possible."]}),"\n",(0,t.jsxs)(n.p,{children:["By placing ",(0,t.jsx)(n.code,{children:"@slowtest"})," token in commit messages, we mark the commit ready for the slow tests framework\n(tests that hit the network). They are run with ",(0,t.jsx)(n.code,{children:"node test-e2e-slow/run-slow-tests.js"})]}),"\n",(0,t.jsx)(n.h2,{id:"windows",children:"Windows"}),"\n",(0,t.jsxs)(n.p,{children:["In cases e2e tests fail with ",(0,t.jsx)(n.code,{children:"Host key verification failed."}),", you might have to create ssh keys\nin the cygwin shall and add them to your github profile."]}),"\n",(0,t.jsxs)(n.ol,{children:["\n",(0,t.jsx)(n.li,{children:"Enter cygwin installed by esy (not the global one)"}),"\n"]}),"\n",(0,t.jsx)(n.pre,{children:(0,t.jsx)(n.code,{className:"language-sh",children:".\\node_modules\\esy-bash\\re\\_build\\default\\bin\\EsyBash.exe bash\n"})}),"\n",(0,t.jsxs)(n.ol,{start:"2",children:["\n",(0,t.jsx)(n.li,{children:"Generate ssh keys"}),"\n"]}),"\n",(0,t.jsx)(n.pre,{children:(0,t.jsx)(n.code,{className:"language-sh",children:"ssh-keygen\n"})}),"\n",(0,t.jsxs)(n.ol,{start:"3",children:["\n",(0,t.jsxs)(n.li,{children:["\n",(0,t.jsx)(n.p,{children:"Add the public key to you Github profile"}),"\n"]}),"\n",(0,t.jsxs)(n.li,{children:["\n",(0,t.jsx)(n.p,{children:"Add the following to the bash rc of the cygwin instance"}),"\n"]}),"\n"]}),"\n",(0,t.jsx)(n.pre,{children:(0,t.jsx)(n.code,{className:"language-sh",children:"eval $(ssh-agent -s)\nssh-add ~/.ssh/id_rsa\n"})})]})}function h(e={}){const{wrapper:n}={...(0,i.a)(),...e.components};return n?(0,t.jsx)(n,{...e,children:(0,t.jsx)(a,{...e})}):a(e)}},1151:(e,n,s)=>{s.d(n,{Z:()=>o,a:()=>d});var t=s(7294);const i={},r=t.createContext(i);function d(e){const n=t.useContext(r);return t.useMemo((function(){return"function"==typeof e?e(n):{...n,...e}}),[n,e])}function o(e){let n;return n=e.disableParentContext?"function"==typeof e.components?e.components(i):e.components||i:d(e.components),t.createElement(r.Provider,{value:n},e.children)}}}]);