"use strict";(self.webpackChunksite_v_3=self.webpackChunksite_v_3||[]).push([[6654],{2450:(e,n,i)=>{i.r(n),i.d(n,{assets:()=>a,contentTitle:()=>o,default:()=>h,frontMatter:()=>s,metadata:()=>c,toc:()=>d});var t=i(5893),r=i(1151);const s={id:"esy-configuration",title:"Configuration"},o=void 0,c={id:"esy-configuration",title:"Configuration",description:"esy can be configured through .esyrc which esy tries to find in the following",source:"@site/../docs/esy-configuration.md",sourceDirName:".",slug:"/esy-configuration",permalink:"/docs/esy-configuration",draft:!1,unlisted:!1,editUrl:"https://github.com/esy/esy/tree/master/docs/../docs/esy-configuration.md",tags:[],version:"current",lastUpdatedBy:"Manas Jayanth",lastUpdatedAt:1719322961,formattedLastUpdatedAt:"Jun 25, 2024",frontMatter:{id:"esy-configuration",title:"Configuration"},sidebar:"docs",previous:{title:"Low Level Commands",permalink:"/docs/low-level-commands"},next:{title:"Node/npm Compatibility",permalink:"/docs/node-compatibility"}},a={},d=[{value:"<code>esy-prefix-path</code>",id:"esy-prefix-path",level:2},{value:"<code>yarn-*</code>",id:"yarn-",level:2}];function l(e){const n={a:"a",code:"code",h2:"h2",li:"li",ol:"ol",p:"p",pre:"pre",ul:"ul",...(0,r.a)(),...e.components};return(0,t.jsxs)(t.Fragment,{children:[(0,t.jsxs)(n.p,{children:["esy can be configured through ",(0,t.jsx)(n.code,{children:".esyrc"})," which esy tries to find in the following\nlocations (sorted by priority):"]}),"\n",(0,t.jsxs)(n.ol,{children:["\n",(0,t.jsxs)(n.li,{children:["Sandbox directory: ",(0,t.jsx)(n.code,{children:".esyrc"})]}),"\n",(0,t.jsxs)(n.li,{children:["Home directory: ",(0,t.jsx)(n.code,{children:"$HOME/.esyrc"})]}),"\n"]}),"\n",(0,t.jsx)(n.p,{children:"The following configuration parameters available:"}),"\n",(0,t.jsxs)(n.ul,{children:["\n",(0,t.jsx)(n.li,{children:(0,t.jsx)(n.a,{href:"#esy-prefix-path",children:(0,t.jsx)(n.code,{children:"esy-prefix-path"})})}),"\n",(0,t.jsx)(n.li,{children:(0,t.jsx)(n.a,{href:"#yarn-",children:(0,t.jsx)(n.code,{children:"yarn-*"})})}),"\n"]}),"\n",(0,t.jsx)(n.p,{children:"Note that some of them could be also controlled via corresponding environment\nvariables."}),"\n",(0,t.jsx)(n.h2,{id:"esy-prefix-path",children:(0,t.jsx)(n.code,{children:"esy-prefix-path"})}),"\n",(0,t.jsxs)(n.p,{children:["Prefix path controls the location where esy puts its installation caches and\nbuild store. By default it is set to ",(0,t.jsx)(n.code,{children:"$HOME/.esy"}),". To override the default\nlocation put the following lines into ",(0,t.jsx)(n.code,{children:".esyrc"}),":"]}),"\n",(0,t.jsx)(n.pre,{children:(0,t.jsx)(n.code,{className:"language-yaml",children:'esy-prefix-path: "/var/lib/esy"\n'})}),"\n",(0,t.jsxs)(n.p,{children:["If relative path is provided then it will be resolved against the directory\n",(0,t.jsx)(n.code,{children:".esyrc"})," resides in."]}),"\n",(0,t.jsxs)(n.p,{children:["Prefix path could also be set using ",(0,t.jsx)(n.code,{children:"$ESY__PREFIX"})," environment variable."]}),"\n",(0,t.jsx)(n.h2,{id:"yarn-",children:(0,t.jsx)(n.code,{children:"yarn-*"})}),"\n",(0,t.jsxs)(n.p,{children:["Any of the yarn configuration parameters can be set in ",(0,t.jsx)(n.code,{children:".esyrc"})," similar to\n",(0,t.jsx)(n.code,{children:".yarnrc"}),". See a corresponding ",(0,t.jsx)(n.a,{href:"https://yarnpkg.com/en/docs/yarnrc",children:"yarn\ndocumentation"})," on the matter."]}),"\n",(0,t.jsxs)(n.p,{children:["Those parameters will be used by ",(0,t.jsx)(n.code,{children:"esy install"})," and ",(0,t.jsx)(n.code,{children:"esy add"})," commands (which use\nyarn under the hood)."]})]})}function h(e={}){const{wrapper:n}={...(0,r.a)(),...e.components};return n?(0,t.jsx)(n,{...e,children:(0,t.jsx)(l,{...e})}):l(e)}},1151:(e,n,i)=>{i.d(n,{Z:()=>c,a:()=>o});var t=i(7294);const r={},s=t.createContext(r);function o(e){const n=t.useContext(s);return t.useMemo((function(){return"function"==typeof e?e(n):{...n,...e}}),[n,e])}function c(e){let n;return n=e.disableParentContext?"function"==typeof e.components?e.components(r):e.components||r:o(e.components),t.createElement(s.Provider,{value:n},e.children)}}}]);