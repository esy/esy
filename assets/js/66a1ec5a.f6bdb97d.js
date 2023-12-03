"use strict";(self.webpackChunksite_v_3=self.webpackChunksite_v_3||[]).push([[2532],{3905:(e,t,n)=>{n.d(t,{Zo:()=>p,kt:()=>m});var r=n(7294);function a(e,t,n){return t in e?Object.defineProperty(e,t,{value:n,enumerable:!0,configurable:!0,writable:!0}):e[t]=n,e}function o(e,t){var n=Object.keys(e);if(Object.getOwnPropertySymbols){var r=Object.getOwnPropertySymbols(e);t&&(r=r.filter((function(t){return Object.getOwnPropertyDescriptor(e,t).enumerable}))),n.push.apply(n,r)}return n}function l(e){for(var t=1;t<arguments.length;t++){var n=null!=arguments[t]?arguments[t]:{};t%2?o(Object(n),!0).forEach((function(t){a(e,t,n[t])})):Object.getOwnPropertyDescriptors?Object.defineProperties(e,Object.getOwnPropertyDescriptors(n)):o(Object(n)).forEach((function(t){Object.defineProperty(e,t,Object.getOwnPropertyDescriptor(n,t))}))}return e}function i(e,t){if(null==e)return{};var n,r,a=function(e,t){if(null==e)return{};var n,r,a={},o=Object.keys(e);for(r=0;r<o.length;r++)n=o[r],t.indexOf(n)>=0||(a[n]=e[n]);return a}(e,t);if(Object.getOwnPropertySymbols){var o=Object.getOwnPropertySymbols(e);for(r=0;r<o.length;r++)n=o[r],t.indexOf(n)>=0||Object.prototype.propertyIsEnumerable.call(e,n)&&(a[n]=e[n])}return a}var s=r.createContext({}),c=function(e){var t=r.useContext(s),n=t;return e&&(n="function"==typeof e?e(t):l(l({},t),e)),n},p=function(e){var t=c(e.components);return r.createElement(s.Provider,{value:t},e.children)},u="mdxType",f={inlineCode:"code",wrapper:function(e){var t=e.children;return r.createElement(r.Fragment,{},t)}},d=r.forwardRef((function(e,t){var n=e.components,a=e.mdxType,o=e.originalType,s=e.parentName,p=i(e,["components","mdxType","originalType","parentName"]),u=c(n),d=a,m=u["".concat(s,".").concat(d)]||u[d]||f[d]||o;return n?r.createElement(m,l(l({ref:t},p),{},{components:n})):r.createElement(m,l({ref:t},p))}));function m(e,t){var n=arguments,a=t&&t.mdxType;if("string"==typeof e||a){var o=n.length,l=new Array(o);l[0]=d;var i={};for(var s in t)hasOwnProperty.call(t,s)&&(i[s]=t[s]);i.originalType=e,i[u]="string"==typeof e?e:a,l[1]=i;for(var c=2;c<o;c++)l[c]=n[c];return r.createElement.apply(null,l)}return r.createElement.apply(null,n)}d.displayName="MDXCreateElement"},5452:(e,t,n)=>{n.r(t),n.d(t,{assets:()=>s,contentTitle:()=>l,default:()=>f,frontMatter:()=>o,metadata:()=>i,toc:()=>c});var r=n(7462),a=(n(7294),n(3905));const o={id:"offline",title:"Offline Builds"},l=void 0,i={unversionedId:"offline",id:"offline",title:"Offline Builds",description:"esy supports workflow where builds should happen on a machine which is",source:"@site/../docs/offline.md",sourceDirName:".",slug:"/offline",permalink:"/docs/offline",draft:!1,editUrl:"https://github.com/esy/esy/tree/master/docs/../docs/offline.md",tags:[],version:"current",lastUpdatedBy:"Manas Jayanth",lastUpdatedAt:1701575103,formattedLastUpdatedAt:"Dec 3, 2023",frontMatter:{id:"offline",title:"Offline Builds"},sidebar:"docs",previous:{title:"Workflow for C/C++ Packages",permalink:"/docs/c-workflow"},next:{title:"How esy works",permalink:"/docs/how-it-works"}},s={},c=[],p={toc:c},u="wrapper";function f(e){let{components:t,...n}=e;return(0,a.kt)(u,(0,r.Z)({},p,n,{components:t,mdxType:"MDXLayout"}),(0,a.kt)("p",null,"esy supports workflow where builds should happen on a machine which is\ncompletely offline (doesn't have network access)."),(0,a.kt)("p",null,"To do that you need to use ",(0,a.kt)("inlineCode",{parentName:"p"},"--cache-tarballs-path")," option when running ",(0,a.kt)("inlineCode",{parentName:"p"},"esy\ninstall")," command:"),(0,a.kt)("ol",null,(0,a.kt)("li",{parentName:"ol"},(0,a.kt)("p",{parentName:"li"},"On a machine which has network access execute:"),(0,a.kt)("pre",{parentName:"li"},(0,a.kt)("code",{parentName:"pre",className:"language-bash"},"% esy install --cache-tarballs-path=./_esyinstall\n")),(0,a.kt)("p",{parentName:"li"},"this will create ",(0,a.kt)("inlineCode",{parentName:"p"},"_esyinstall")," directory with all downloaded dependencies'\nsources.")),(0,a.kt)("li",{parentName:"ol"},(0,a.kt)("p",{parentName:"li"},"Tranfer an entire project directory along with ",(0,a.kt)("inlineCode",{parentName:"p"},"_esyinstall")," to a machine\nwhich doesn't have access to an external network.")),(0,a.kt)("li",{parentName:"ol"},(0,a.kt)("p",{parentName:"li"},"Execute the same installation command"),(0,a.kt)("pre",{parentName:"li"},(0,a.kt)("code",{parentName:"pre",className:"language-bash"},"% esy install --cache-tarballs-path=./_esyinstall\n")),(0,a.kt)("p",{parentName:"li"},"which will unpack all source tarballs into cache.")),(0,a.kt)("li",{parentName:"ol"},(0,a.kt)("p",{parentName:"li"},"Run"),(0,a.kt)("pre",{parentName:"li"},(0,a.kt)("code",{parentName:"pre",className:"language-bash"},"% esy build\n")),(0,a.kt)("p",{parentName:"li"},"and other esy commands."))))}f.isMDXComponent=!0}}]);