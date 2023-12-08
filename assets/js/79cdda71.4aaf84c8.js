"use strict";(self.webpackChunksite_v_3=self.webpackChunksite_v_3||[]).push([[4461],{6995:(e,n,t)=>{t.r(n),t.d(n,{assets:()=>c,contentTitle:()=>a,default:()=>h,frontMatter:()=>o,metadata:()=>r,toc:()=>l});var s=t(5893),i=t(1151);const o={author:"Manas Jayanth",authorURL:"https://twitter.com/ManasJayanth",title:"New release - 0.6.0 \ud83c\udf89"},a=void 0,r={permalink:"/blog/2020/01/12/0.6.0",source:"@site/blog/2020-01-12-0.6.0.md",title:"New release - 0.6.0 \ud83c\udf89",description:"We went quite again for a while with the blog - between the last post, we released 0.5.* and now 0.6.0.",date:"2020-01-12T00:00:00.000Z",formattedDate:"January 12, 2020",tags:[],readingTime:1.73,hasTruncateMarker:!0,authors:[{name:"Manas Jayanth",url:"https://twitter.com/ManasJayanth"}],frontMatter:{author:"Manas Jayanth",authorURL:"https://twitter.com/ManasJayanth",title:"New release - 0.6.0 \ud83c\udf89"},unlisted:!1,nextItem:{title:"What's new in esy 0.4.x",permalink:"/blog/2018/12/27/0.4.x"}},c={authorsImageUrls:[void 0]},l=[{value:"esy cleanup",id:"esy-cleanup",level:3},{value:"Improved solver performance with better CUDF encoding",id:"improved-solver-performance-with-better-cudf-encoding",level:3},{value:"Recursive fetching of submodules, when building packages from source",id:"recursive-fetching-of-submodules-when-building-packages-from-source",level:3},{value:"Long paths on Windows",id:"long-paths-on-windows",level:3},{value:"Other Notable fixes",id:"other-notable-fixes",level:3}];function d(e){const n={a:"a",code:"code",h3:"h3",li:"li",p:"p",ul:"ul",...(0,i.a)(),...e.components};return(0,s.jsxs)(s.Fragment,{children:[(0,s.jsx)(n.p,{children:"We went quite again for a while with the blog - between the last post, we released 0.5.* and now 0.6.0."}),"\n",(0,s.jsx)(n.p,{children:"This time received contributions from 28 contributors! Thank you\neveryone! Let's take a quick look at what new in 0.6.0."}),"\n",(0,s.jsx)(n.h3,{id:"esy-cleanup",children:"esy cleanup"}),"\n",(0,s.jsxs)(n.p,{children:["We added a sub-command ",(0,s.jsx)(n.code,{children:"cleanup"})," to reclaim disk space by purging\nunused builds. Over time, cached builds would just accumulate in\n",(0,s.jsx)(n.code,{children:"~/.esy"})," and the only way to reclaim space was to delete it\nentirely. Users had no way of knowing which cached builds were in use\nby projects and would end up seeing long build times again after deleting the the cached directory."]}),"\n",(0,s.jsxs)(n.p,{children:[(0,s.jsx)(n.code,{children:"esy cleanup"})," takes in a list of projects in use as arguments and\nremoves all cached builds not needed by any of them:"]}),"\n",(0,s.jsx)(n.p,{children:"$ esy cleanup ./project/in/use ./another/project"}),"\n",(0,s.jsxs)(n.p,{children:["See ",(0,s.jsx)(n.a,{href:"https://esy.sh/docs/en/commands.html#esy-cleanup",children:"docs"})," for more information."]}),"\n",(0,s.jsx)(n.h3,{id:"improved-solver-performance-with-better-cudf-encoding",children:"Improved solver performance with better CUDF encoding"}),"\n",(0,s.jsxs)(n.p,{children:["We re-worked how we encode dependencies which improved solver\nperformance, fixed ",(0,s.jsx)(n.a,{href:"https://github.com/esy/esy/issues/883",children:"critical bug"}),". More on this can found at issue ",(0,s.jsx)(n.a,{href:"https://github.com/esy/esy/issues/888",children:"#888"})]}),"\n",(0,s.jsx)(n.h3,{id:"recursive-fetching-of-submodules-when-building-packages-from-source",children:"Recursive fetching of submodules, when building packages from source"}),"\n",(0,s.jsx)(n.p,{children:"As a move towards ensuring better compatibility with opam, we\nrecursively fetch submodules when fetching from git sources."}),"\n",(0,s.jsx)(n.p,{children:"Now esy can install and build packages from git/github even if they depend on\nsubmodules."}),"\n",(0,s.jsx)(n.h3,{id:"long-paths-on-windows",children:"Long paths on Windows"}),"\n",(0,s.jsx)(n.p,{children:"We were earlier constrained to only use 33 characters in the\nartifact paths in our binaries on Windows - this caused\nrelocatability issues and delayed our plans of fetching prebuilts\nfor esy sandbox. With this release, esy now enables long paths on\nsupported Windows machines and brings back relocatability (and\nthere shorted build times with prebuilts) back on the table."}),"\n",(0,s.jsx)(n.h3,{id:"other-notable-fixes",children:"Other Notable fixes"}),"\n",(0,s.jsx)(n.p,{children:"Besides that 0.6.0 contains fixes for not a small number of bugs, many doc\nupdates and small quality-of-life improvements. Some things worth mentioning:"}),"\n",(0,s.jsxs)(n.ul,{children:["\n",(0,s.jsx)(n.li,{children:"More robust project discovery"}),"\n",(0,s.jsx)(n.li,{children:"Improved git source parsing"}),"\n",(0,s.jsx)(n.li,{children:"Test suite improvements"}),"\n",(0,s.jsx)(n.li,{children:"New command esy run-script SCRIPTNAME which provides a future proof way of\nrunning package.json scripts"}),"\n"]}),"\n",(0,s.jsxs)(n.p,{children:["The entire changelog can be found ",(0,s.jsx)(n.a,{href:"https://github.com/esy/esy/blob/master/CHANGELOG.md#060--latest",children:"here"}),"."]})]})}function h(e={}){const{wrapper:n}={...(0,i.a)(),...e.components};return n?(0,s.jsx)(n,{...e,children:(0,s.jsx)(d,{...e})}):d(e)}},1151:(e,n,t)=>{t.d(n,{Z:()=>r,a:()=>a});var s=t(7294);const i={},o=s.createContext(i);function a(e){const n=s.useContext(o);return s.useMemo((function(){return"function"==typeof e?e(n):{...n,...e}}),[n,e])}function r(e){let n;return n=e.disableParentContext?"function"==typeof e.components?e.components(i):e.components||i:a(e.components),s.createElement(o.Provider,{value:n},e.children)}}}]);