"use strict";(self.webpackChunksite_v_3=self.webpackChunksite_v_3||[]).push([[685],{1465:(e,n,s)=>{s.r(n),s.d(n,{assets:()=>d,contentTitle:()=>t,default:()=>p,frontMatter:()=>l,metadata:()=>r,toc:()=>c});var o=s(5893),i=s(1151);const l={id:"opam-workflow",title:"Workflow for opam Packages"},t=void 0,r={id:"opam-workflow",title:"Workflow for opam Packages",description:"This feature is experimental",source:"@site/../docs/opam-workflow.md",sourceDirName:".",slug:"/opam-workflow",permalink:"/docs/opam-workflow",draft:!1,unlisted:!1,editUrl:"https://github.com/esy/esy/tree/master/docs/../docs/opam-workflow.md",tags:[],version:"current",lastUpdatedBy:"prometheansacrifice",lastUpdatedAt:1725276666,formattedLastUpdatedAt:"Sep 2, 2024",frontMatter:{id:"opam-workflow",title:"Workflow for opam Packages"},sidebar:"docs",previous:{title:"Building npm Releases",permalink:"/docs/npm-release"},next:{title:"Workflow for C/C++ Packages",permalink:"/docs/c-workflow"}},d={},c=[{value:"Installing dependencies",id:"installing-dependencies",level:2},{value:"Building project",id:"building-project",level:2}];function a(e){const n={blockquote:"blockquote",code:"code",h2:"h2",li:"li",p:"p",pre:"pre",strong:"strong",ul:"ul",...(0,i.a)(),...e.components};return(0,o.jsxs)(o.Fragment,{children:[(0,o.jsxs)(n.blockquote,{children:["\n",(0,o.jsx)(n.p,{children:(0,o.jsx)(n.strong,{children:"This feature is experimental"})}),"\n",(0,o.jsx)(n.p,{children:"This feature didn't receive a lot of testing, please report any issues found\nand feature requests."}),"\n"]}),"\n",(0,o.jsx)(n.p,{children:"esy supports developing opam projects directly, the workflow is similar to esy\nprojects:"}),"\n",(0,o.jsx)(n.pre,{children:(0,o.jsx)(n.code,{className:"language-bash",children:"% git clone https://github.com/rgrinberg/ocaml-semver.git\n% cd ocaml-semver\n% esy install\n% esy build\n"})}),"\n",(0,o.jsx)(n.h2,{id:"installing-dependencies",children:"Installing dependencies"}),"\n",(0,o.jsxs)(n.p,{children:["To install project dependencies run ",(0,o.jsx)(n.code,{children:"esy install"})," command."]}),"\n",(0,o.jsxs)(n.p,{children:["This will read dependencies from all ",(0,o.jsx)(n.code,{children:"*.opam"})," files found in a project and\ninstall them locally into the sandbox."]}),"\n",(0,o.jsx)(n.p,{children:"Note that even compiler is installed locally to the project, you don't need to\nmanage switches manually like in opam:"}),"\n",(0,o.jsx)(n.pre,{children:(0,o.jsx)(n.code,{children:"% esy ocamlc\n"})}),"\n",(0,o.jsxs)(n.p,{children:["Will run the compiler version defined by the project's constraints set in\n",(0,o.jsx)(n.code,{children:"*.opam"})," files."]}),"\n",(0,o.jsx)(n.h2,{id:"building-project",children:"Building project"}),"\n",(0,o.jsxs)(n.p,{children:["To build project dependencies and the project itself run ",(0,o.jsx)(n.code,{children:"esy build"})," command."]}),"\n",(0,o.jsxs)(n.p,{children:["The ",(0,o.jsx)(n.code,{children:"esy build"})," command  performs differently depending on the number of opam\nfiles found in a project directory:"]}),"\n",(0,o.jsxs)(n.ul,{children:["\n",(0,o.jsxs)(n.li,{children:["\n",(0,o.jsxs)(n.p,{children:["In case there's a single ",(0,o.jsx)(n.code,{children:"*.opam"})," file found ",(0,o.jsx)(n.code,{children:"esy build"})," will build all\ndependencies and then execute ",(0,o.jsx)(n.code,{children:"build"})," commands found in opam metadata."]}),"\n"]}),"\n",(0,o.jsxs)(n.li,{children:["\n",(0,o.jsxs)(n.p,{children:["In case there are multiple ",(0,o.jsx)(n.code,{children:"*.opam"})," files found ",(0,o.jsx)(n.code,{children:"esy build"})," will build all\ndependencies and stop. To build the project itself users are supposed to use the\ncommand which is specified by the project's workflow but run inside the esy's\nbuild environment."]}),"\n",(0,o.jsx)(n.p,{children:"In case of a dune-based project this is usually means:"}),"\n",(0,o.jsx)(n.pre,{children:(0,o.jsx)(n.code,{className:"language-bash",children:"% esy b dune build\n"})}),"\n"]}),"\n"]})]})}function p(e={}){const{wrapper:n}={...(0,i.a)(),...e.components};return n?(0,o.jsx)(n,{...e,children:(0,o.jsx)(a,{...e})}):a(e)}},1151:(e,n,s)=>{s.d(n,{Z:()=>r,a:()=>t});var o=s(7294);const i={},l=o.createContext(i);function t(e){const n=o.useContext(l);return o.useMemo((function(){return"function"==typeof e?e(n):{...n,...e}}),[n,e])}function r(e){let n;return n=e.disableParentContext?"function"==typeof e.components?e.components(i):e.components||i:t(e.components),o.createElement(l.Provider,{value:n},e.children)}}}]);