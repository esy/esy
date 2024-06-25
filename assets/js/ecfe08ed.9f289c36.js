"use strict";(self.webpackChunksite_v_3=self.webpackChunksite_v_3||[]).push([[8382],{7199:(e,n,t)=>{t.r(n),t.d(n,{assets:()=>c,contentTitle:()=>r,default:()=>a,frontMatter:()=>o,metadata:()=>d,toc:()=>l});var i=t(5893),s=t(1151);const o={id:"contributing",title:"Contributing"},r=void 0,d={id:"contributing",title:"Contributing",description:"Editor Integration For New Editor:",source:"@site/../docs/contributing.md",sourceDirName:".",slug:"/contributing",permalink:"/docs/contributing",draft:!1,unlisted:!1,editUrl:"https://github.com/esy/esy/tree/master/docs/../docs/contributing.md",tags:[],version:"current",lastUpdatedBy:"Manas Jayanth",lastUpdatedAt:1719322961,formattedLastUpdatedAt:"Jun 25, 2024",frontMatter:{id:"contributing",title:"Contributing"}},c={},l=[{value:"Editor Integration For New Editor:",id:"editor-integration-for-new-editor",level:2},{value:"Helping Out With Editor Integration",id:"helping-out-with-editor-integration",level:3}];function h(e){const n={a:"a",code:"code",h2:"h2",h3:"h3",li:"li",p:"p",table:"table",tbody:"tbody",td:"td",th:"th",thead:"thead",tr:"tr",ul:"ul",...(0,s.a)(),...e.components};return(0,i.jsxs)(i.Fragment,{children:[(0,i.jsx)(n.h2,{id:"editor-integration-for-new-editor",children:"Editor Integration For New Editor:"}),"\n",(0,i.jsx)(n.p,{children:"Currently supported editor integrations:"}),"\n",(0,i.jsxs)(n.table,{children:[(0,i.jsx)(n.thead,{children:(0,i.jsxs)(n.tr,{children:[(0,i.jsx)(n.th,{children:"LSP"}),(0,i.jsx)(n.th,{children:"Vim"}),(0,i.jsx)(n.th,{children:"Emacs"})]})}),(0,i.jsx)(n.tbody,{children:(0,i.jsxs)(n.tr,{children:[(0,i.jsx)(n.td,{children:(0,i.jsx)(n.a,{href:"https://github.com/freebroccolo/ocaml-language-server",children:"DONE"})}),(0,i.jsx)(n.td,{children:(0,i.jsx)(n.a,{href:"https://github.com/jordwalke/vim-reason",children:"DONE"})}),(0,i.jsx)(n.td,{children:"HELP APPRECIATED"})]})})]}),"\n",(0,i.jsxs)(n.ul,{children:["\n",(0,i.jsxs)(n.li,{children:["Note: The Vim plugin does not yet have support for ",(0,i.jsx)(n.code,{children:".ml"})," file extensions and\ncurrently only activates upon ",(0,i.jsx)(n.code,{children:".re"}),"."]}),"\n",(0,i.jsx)(n.li,{children:"Note: For VSCode, editing multiple projects simultaneously requires a separate\nwindow per project."}),"\n"]}),"\n",(0,i.jsxs)(n.p,{children:["When you edit an ",(0,i.jsx)(n.code,{children:"esy"})," project in editors with supported integration,\nthe dev environment will be correctly constructed so that\nall your dependencies are seen by the editor, while maintaining isolation\nbetween multiple projects."]}),"\n",(0,i.jsxs)(n.p,{children:['That means your autocomplete "Just Works" according to what is listed in your\n',(0,i.jsx)(n.code,{children:"esy.json"}),"/",(0,i.jsx)(n.code,{children:"package.json"}),", and you can edit multiple projects simultaneously\neven when each of these projects have very different versions of dependencies\n(including compiler versions)."]}),"\n",(0,i.jsxs)(n.p,{children:[(0,i.jsx)(n.a,{href:"https://github.com/esy-ocaml/hello-reason",children:"hello-reason"})," is an example project\nthat uses ",(0,i.jsx)(n.code,{children:"esy"})," to manage dependencies and works well with either of those\neditor plugins mentioned. Simply clone that project, ",(0,i.jsx)(n.code,{children:"esy"}),", and then open a ",(0,i.jsx)(n.code,{children:".re"})," file in any of the supported editors/plugins\nmentioned."]}),"\n",(0,i.jsx)(n.h3,{id:"helping-out-with-editor-integration",children:"Helping Out With Editor Integration"}),"\n",(0,i.jsxs)(n.p,{children:["Help with the Emacs plugin is appreciated, and if contributing supobprt it is encouraged\nthat you model the plugin implementation after the ",(0,i.jsx)(n.code,{children:"vim-reason"})," plugin.\nAt a high level here is what editor support should do:"]}),"\n",(0,i.jsxs)(n.ul,{children:["\n",(0,i.jsxs)(n.li,{children:["For each buffer/file opened, determine which ",(0,i.jsx)(n.code,{children:"esy"})," project it belongs to, if any."]}),"\n",(0,i.jsxs)(n.li,{children:['For each project, determine the "phase".',"\n",(0,i.jsxs)(n.ul,{children:["\n",(0,i.jsxs)(n.li,{children:["The phase is either, ",(0,i.jsx)(n.code,{children:"'no-esy-field'"}),", ",(0,i.jsx)(n.code,{children:"'uninitialized', "}),"'installed'",(0,i.jsx)(n.code,{children:", or "}),"'built'`."]}),"\n"]}),"\n"]}),"\n",(0,i.jsx)(n.li,{children:"Provide some commands such as"}),"\n",(0,i.jsxs)(n.li,{children:["Implement some commands such as:","\n",(0,i.jsxs)(n.ul,{children:["\n",(0,i.jsxs)(n.li,{children:[(0,i.jsx)(n.code,{children:"EsyFetchProjectInfo"}),": Show the project's ",(0,i.jsx)(n.code,{children:"package.json"}),', and the "stage" of\nthe project.']}),"\n",(0,i.jsxs)(n.li,{children:[(0,i.jsx)(n.code,{children:"Reset"}),": Reset any caches, and internal knowledge of buffers/projects."]}),"\n",(0,i.jsxs)(n.li,{children:[(0,i.jsx)(n.code,{children:"EsyExec"}),": Execute a command in the current buffer's project environment."]}),"\n",(0,i.jsxs)(n.li,{children:[(0,i.jsx)(n.code,{children:"EsyBuilds"}),": Run the ",(0,i.jsx)(n.code,{children:"esy ls-builds"})," command."]}),"\n",(0,i.jsxs)(n.li,{children:[(0,i.jsx)(n.code,{children:"EsyLibs"}),": Run the ",(0,i.jsx)(n.code,{children:"esy ls-libs"})," command."]}),"\n",(0,i.jsxs)(n.li,{children:[(0,i.jsx)(n.code,{children:"EsyModules"}),": Run the ",(0,i.jsx)(n.code,{children:"esy ls-modules"})," command."]}),"\n"]}),"\n"]}),"\n",(0,i.jsxs)(n.li,{children:["As soon as the phase is finally in the ",(0,i.jsx)(n.code,{children:"built"})," state, initialize a merlin process\nupon the first ",(0,i.jsx)(n.code,{children:".re"}),"/",(0,i.jsx)(n.code,{children:".ml"})," file opened. That should use the ",(0,i.jsx)(n.code,{children:"EsyExec"})," functionality\nto ensure the process is being started within the correct environment per project."]}),"\n"]}),"\n",(0,i.jsxs)(n.p,{children:["See the implementation of ",(0,i.jsx)(n.code,{children:"vim-reason"})," ",(0,i.jsx)(n.a,{href:"https://github.com/jordwalke/vim-reason/blob/master/autoload/esy.vim",children:"here"})]})]})}function a(e={}){const{wrapper:n}={...(0,s.a)(),...e.components};return n?(0,i.jsx)(n,{...e,children:(0,i.jsx)(h,{...e})}):h(e)}},1151:(e,n,t)=>{t.d(n,{Z:()=>d,a:()=>r});var i=t(7294);const s={},o=i.createContext(s);function r(e){const n=i.useContext(o);return i.useMemo((function(){return"function"==typeof e?e(n):{...n,...e}}),[n,e])}function d(e){let n;return n=e.disableParentContext?"function"==typeof e.components?e.components(s):e.components||s:r(e.components),i.createElement(o.Provider,{value:n},e.children)}}}]);