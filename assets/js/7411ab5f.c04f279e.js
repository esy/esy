"use strict";(self.webpackChunksite_v_3=self.webpackChunksite_v_3||[]).push([[234],{3905:(e,n,t)=>{t.d(n,{Zo:()=>c,kt:()=>m});var a=t(7294);function o(e,n,t){return n in e?Object.defineProperty(e,n,{value:t,enumerable:!0,configurable:!0,writable:!0}):e[n]=t,e}function r(e,n){var t=Object.keys(e);if(Object.getOwnPropertySymbols){var a=Object.getOwnPropertySymbols(e);n&&(a=a.filter((function(n){return Object.getOwnPropertyDescriptor(e,n).enumerable}))),t.push.apply(t,a)}return t}function i(e){for(var n=1;n<arguments.length;n++){var t=null!=arguments[n]?arguments[n]:{};n%2?r(Object(t),!0).forEach((function(n){o(e,n,t[n])})):Object.getOwnPropertyDescriptors?Object.defineProperties(e,Object.getOwnPropertyDescriptors(t)):r(Object(t)).forEach((function(n){Object.defineProperty(e,n,Object.getOwnPropertyDescriptor(t,n))}))}return e}function l(e,n){if(null==e)return{};var t,a,o=function(e,n){if(null==e)return{};var t,a,o={},r=Object.keys(e);for(a=0;a<r.length;a++)t=r[a],n.indexOf(t)>=0||(o[t]=e[t]);return o}(e,n);if(Object.getOwnPropertySymbols){var r=Object.getOwnPropertySymbols(e);for(a=0;a<r.length;a++)t=r[a],n.indexOf(t)>=0||Object.prototype.propertyIsEnumerable.call(e,t)&&(o[t]=e[t])}return o}var p=a.createContext({}),s=function(e){var n=a.useContext(p),t=n;return e&&(t="function"==typeof e?e(n):i(i({},n),e)),t},c=function(e){var n=s(e.components);return a.createElement(p.Provider,{value:n},e.children)},k="mdxType",u={inlineCode:"code",wrapper:function(e){var n=e.children;return a.createElement(a.Fragment,{},n)}},d=a.forwardRef((function(e,n){var t=e.components,o=e.mdxType,r=e.originalType,p=e.parentName,c=l(e,["components","mdxType","originalType","parentName"]),k=s(t),d=o,m=k["".concat(p,".").concat(d)]||k[d]||u[d]||r;return t?a.createElement(m,i(i({ref:n},c),{},{components:t})):a.createElement(m,i({ref:n},c))}));function m(e,n){var t=arguments,o=n&&n.mdxType;if("string"==typeof e||o){var r=t.length,i=new Array(r);i[0]=d;var l={};for(var p in n)hasOwnProperty.call(n,p)&&(l[p]=n[p]);l.originalType=e,l[k]="string"==typeof e?e:o,i[1]=l;for(var s=2;s<r;s++)i[s]=t[s];return a.createElement.apply(null,i)}return a.createElement.apply(null,t)}d.displayName="MDXCreateElement"},3790:(e,n,t)=>{t.r(n),t.d(n,{assets:()=>p,contentTitle:()=>i,default:()=>u,frontMatter:()=>r,metadata:()=>l,toc:()=>s});var a=t(7462),o=(t(7294),t(3905));const r={id:"linking-workflow",title:"Linking Packages in Development"},i=void 0,l={unversionedId:"linking-workflow",id:"linking-workflow",title:"Linking Packages in Development",description:"esy allows to link a package in development to a project so that changes to the",source:"@site/../docs/linking-workflow.md",sourceDirName:".",slug:"/linking-workflow",permalink:"/docs/linking-workflow",draft:!1,editUrl:"https://github.com/esy/esy/tree/master/docs/../docs/linking-workflow.md",tags:[],version:"current",lastUpdatedBy:"Manas Jayanth",lastUpdatedAt:1701575103,formattedLastUpdatedAt:"Dec 3, 2023",frontMatter:{id:"linking-workflow",title:"Linking Packages in Development"},sidebar:"docs",previous:{title:"Using Unreleased Packages",permalink:"/docs/using-repo-sources-workflow"},next:{title:"Concepts",permalink:"/docs/concepts"}},p={},s=[{value:"With esy packages",id:"with-esy-packages",level:2},{value:"With opam packages",id:"with-opam-packages",level:2}],c={toc:s},k="wrapper";function u(e){let{components:n,...t}=e;return(0,o.kt)(k,(0,a.Z)({},c,t,{components:n,mdxType:"MDXLayout"}),(0,o.kt)("p",null,'esy allows to link a package in development to a project so that changes to the\nlinked package are observed in "real time" without the need to keep\nre-installing it.'),(0,o.kt)("p",null,"When building a project esy will check & rebuild linked packages on any changes\nin their source trees."),(0,o.kt)("h2",{id:"with-esy-packages"},"With esy packages"),(0,o.kt)("p",null,"To link a package to the project add a special ",(0,o.kt)("inlineCode",{parentName:"p"},"link:")," resolution to project's\n",(0,o.kt)("a",{parentName:"p",href:"configuration.html#resolutions"},(0,o.kt)("inlineCode",{parentName:"a"},"resolutions"))," field alongside the dependency declaration:"),(0,o.kt)("pre",null,(0,o.kt)("code",{parentName:"pre",className:"language-json"},'"dependencies": {\n  "reason": "*"\n},\n"resolutions": {\n  "reason": "link:../path/to/reason/checkout"\n}\n')),(0,o.kt)("p",null,"If you are linking to a folder with many esy packages in it, use the path to the\n",(0,o.kt)("inlineCode",{parentName:"p"},"json")," file that will be use to resolve the dependency, for example:"),(0,o.kt)("pre",null,(0,o.kt)("code",{parentName:"pre",className:"language-json"},'"dependencies": {\n  "refmterr": "*",\n},\n"resolutions": {\n  "refmterr": "link:../reason-native/refmterr.json"\n}\n')),(0,o.kt)("blockquote",null,(0,o.kt)("p",{parentName:"blockquote"},"Why ",(0,o.kt)("inlineCode",{parentName:"p"},"resolutions"),"?"),(0,o.kt)("p",{parentName:"blockquote"},"This is because in case any other package in the project's sandbox depends on\n",(0,o.kt)("inlineCode",{parentName:"p"},"reason")," package then it will certainly conflict with ",(0,o.kt)("inlineCode",{parentName:"p"},"link:")," declaration\n(nothing conforms to ",(0,o.kt)("inlineCode",{parentName:"p"},"link:")," except the same link)."),(0,o.kt)("p",{parentName:"blockquote"},"Thus we use ",(0,o.kt)("inlineCode",{parentName:"p"},"resolutions")," so that constraint solver is forced to use ",(0,o.kt)("inlineCode",{parentName:"p"},"link:"),"\ndeclaration in every place ",(0,o.kt)("inlineCode",{parentName:"p"},"reason")," package is required.")),(0,o.kt)("h2",{id:"with-opam-packages"},"With opam packages"),(0,o.kt)("p",null,"It is also possible to link an opam package, the mechanism is the similar but\nyou need to specify a path to an ",(0,o.kt)("inlineCode",{parentName:"p"},"*.opam")," file in a ",(0,o.kt)("inlineCode",{parentName:"p"},"link:")," resolution:"),(0,o.kt)("pre",null,(0,o.kt)("code",{parentName:"pre",className:"language-json"},'"dependencies": {\n  "@opam/lwt": "*",\n  "@opam/lwt_ppx": "*"\n},\n"resolutions": {\n  "@opam/lwt": "link:../path/to/lwt/checkout/lwt.opam",\n  "@opam/lwt_ppx": "link:../path/to/lwt/checkout/lwt_ppx.opam"\n}\n')),(0,o.kt)("p",null,"The need to specify an ",(0,o.kt)("inlineCode",{parentName:"p"},"*.opam")," file is because an opam package development repository can contain multiple packages."))}u.isMDXComponent=!0}}]);