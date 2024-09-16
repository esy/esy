"use strict";(self.webpackChunksite_v_3=self.webpackChunksite_v_3||[]).push([[9895],{1979:(e,n,s)=>{s.r(n),s.d(n,{assets:()=>o,contentTitle:()=>a,default:()=>p,frontMatter:()=>c,metadata:()=>l,toc:()=>r});var i=s(4848),t=s(8453);const c={id:"node-compatibility",title:"Node/npm Compatibility"},a=void 0,l={id:"node-compatibility",title:"Node/npm Compatibility",description:"esy can install packages from npm registry.",source:"@site/../docs/node-compatibility.md",sourceDirName:".",slug:"/node-compatibility",permalink:"/docs/node-compatibility",draft:!1,unlisted:!1,editUrl:"https://github.com/esy/esy/tree/master/docs/../docs/node-compatibility.md",tags:[],version:"current",lastUpdatedBy:"prometheansacrifice",lastUpdatedAt:1726472989,formattedLastUpdatedAt:"Sep 16, 2024",frontMatter:{id:"node-compatibility",title:"Node/npm Compatibility"},sidebar:"docs",previous:{title:"Configuration",permalink:"/docs/esy-configuration"},next:{title:"Frequently Asked Questions",permalink:"/docs/faqs"}},o={},r=[{value:"Accessing installed JS packages",id:"accessing-installed-js-packages",level:2},{value:"Caveats",id:"caveats",level:2}];function d(e){const n={a:"a",code:"code",h2:"h2",li:"li",p:"p",pre:"pre",ul:"ul",...(0,t.R)(),...e.components};return(0,i.jsxs)(i.Fragment,{children:[(0,i.jsx)(n.p,{children:"esy can install packages from npm registry."}),"\n",(0,i.jsxs)(n.p,{children:["This means ",(0,i.jsx)(n.code,{children:"esy install"})," can also install packages which contain JavaScript\ncode."]}),"\n",(0,i.jsx)(n.h2,{id:"accessing-installed-js-packages",children:"Accessing installed JS packages"}),"\n",(0,i.jsxs)(n.p,{children:["As opposed to a standard way of installing packages into project's\n",(0,i.jsx)(n.code,{children:"node_modules"})," directory esy uses ",(0,i.jsx)(n.a,{href:"https://github.com/arcanis/rfcs/blob/6fc13d52f43eff45b7b46b707f3115cc63d0ea5f/accepted/0000-plug-an-play.md",children:"plug'n'play installation mechanism"}),"\n(pnp for short) pioneered by ",(0,i.jsx)(n.a,{href:"https://github.com/yarnpkg/yarn",children:"yarn"}),"."]}),"\n",(0,i.jsx)(n.p,{children:"There are few differences though:"}),"\n",(0,i.jsxs)(n.ul,{children:["\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsxs)(n.p,{children:["esy puts pnp runtime not as ",(0,i.jsx)(n.code,{children:".pnp.js"})," but as ",(0,i.jsx)(n.code,{children:"_esy/default/pnp.js"})," (or\n",(0,i.jsx)(n.code,{children:"_esy/NAME/pnp.js"})," for a named sandbox with name ",(0,i.jsx)(n.code,{children:"NAME"}),")."]}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsxs)(n.p,{children:["To execute pnp enabled ",(0,i.jsx)(n.code,{children:"node"})," one uses ",(0,i.jsx)(n.code,{children:"esy node"})," invocation."]}),"\n"]}),"\n"]}),"\n",(0,i.jsxs)(n.p,{children:["All binaries installed with npm packages are accessible via ",(0,i.jsx)(n.code,{children:"esy COMMAND"}),"\ninvocation, few example:"]}),"\n",(0,i.jsxs)(n.ul,{children:["\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsxs)(n.p,{children:["To run webpack (comes from ",(0,i.jsx)(n.code,{children:"webpack-cli"}),"):"]}),"\n",(0,i.jsx)(n.pre,{children:(0,i.jsx)(n.code,{className:"language-bash",children:"% esy webpack\n"})}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsxs)(n.p,{children:["To run ",(0,i.jsx)(n.code,{children:"flow"})," (comes from ",(0,i.jsx)(n.code,{children:"flow-bin"})," package):"]}),"\n",(0,i.jsx)(n.pre,{children:(0,i.jsx)(n.code,{className:"language-bash",children:"% esy flow\n"})}),"\n"]}),"\n"]}),"\n",(0,i.jsx)(n.h2,{id:"caveats",children:"Caveats"}),"\n",(0,i.jsxs)(n.ul,{children:["\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsx)(n.p,{children:"Not all npm packages currently support being installed with plug'n'play\ninstallation mechanism."}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["\n",(0,i.jsxs)(n.p,{children:["Not all npm lifecycle hooks are supported right now (only ",(0,i.jsx)(n.code,{children:"install"})," and\n",(0,i.jsx)(n.code,{children:"postinstall"})," are being run)."]}),"\n"]}),"\n"]})]})}function p(e={}){const{wrapper:n}={...(0,t.R)(),...e.components};return n?(0,i.jsx)(n,{...e,children:(0,i.jsx)(d,{...e})}):d(e)}},8453:(e,n,s)=>{s.d(n,{R:()=>a,x:()=>l});var i=s(6540);const t={},c=i.createContext(t);function a(e){const n=i.useContext(c);return i.useMemo((function(){return"function"==typeof e?e(n):{...n,...e}}),[n,e])}function l(e){let n;return n=e.disableParentContext?"function"==typeof e.components?e.components(t):e.components||t:a(e.components),i.createElement(c.Provider,{value:n},e.children)}}}]);