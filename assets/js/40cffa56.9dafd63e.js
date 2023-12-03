"use strict";(self.webpackChunksite_v_3=self.webpackChunksite_v_3||[]).push([[6371],{3905:(e,t,n)=>{n.d(t,{Zo:()=>u,kt:()=>h});var a=n(7294);function o(e,t,n){return t in e?Object.defineProperty(e,t,{value:n,enumerable:!0,configurable:!0,writable:!0}):e[t]=n,e}function i(e,t){var n=Object.keys(e);if(Object.getOwnPropertySymbols){var a=Object.getOwnPropertySymbols(e);t&&(a=a.filter((function(t){return Object.getOwnPropertyDescriptor(e,t).enumerable}))),n.push.apply(n,a)}return n}function s(e){for(var t=1;t<arguments.length;t++){var n=null!=arguments[t]?arguments[t]:{};t%2?i(Object(n),!0).forEach((function(t){o(e,t,n[t])})):Object.getOwnPropertyDescriptors?Object.defineProperties(e,Object.getOwnPropertyDescriptors(n)):i(Object(n)).forEach((function(t){Object.defineProperty(e,t,Object.getOwnPropertyDescriptor(n,t))}))}return e}function r(e,t){if(null==e)return{};var n,a,o=function(e,t){if(null==e)return{};var n,a,o={},i=Object.keys(e);for(a=0;a<i.length;a++)n=i[a],t.indexOf(n)>=0||(o[n]=e[n]);return o}(e,t);if(Object.getOwnPropertySymbols){var i=Object.getOwnPropertySymbols(e);for(a=0;a<i.length;a++)n=i[a],t.indexOf(n)>=0||Object.prototype.propertyIsEnumerable.call(e,n)&&(o[n]=e[n])}return o}var l=a.createContext({}),p=function(e){var t=a.useContext(l),n=t;return e&&(n="function"==typeof e?e(t):s(s({},t),e)),n},u=function(e){var t=p(e.components);return a.createElement(l.Provider,{value:t},e.children)},d="mdxType",c={inlineCode:"code",wrapper:function(e){var t=e.children;return a.createElement(a.Fragment,{},t)}},m=a.forwardRef((function(e,t){var n=e.components,o=e.mdxType,i=e.originalType,l=e.parentName,u=r(e,["components","mdxType","originalType","parentName"]),d=p(n),m=o,h=d["".concat(l,".").concat(m)]||d[m]||c[m]||i;return n?a.createElement(h,s(s({ref:t},u),{},{components:n})):a.createElement(h,s({ref:t},u))}));function h(e,t){var n=arguments,o=t&&t.mdxType;if("string"==typeof e||o){var i=n.length,s=new Array(i);s[0]=m;var r={};for(var l in t)hasOwnProperty.call(t,l)&&(r[l]=t[l]);r.originalType=e,r[d]="string"==typeof e?e:o,s[1]=r;for(var p=2;p<i;p++)s[p]=n[p];return a.createElement.apply(null,s)}return a.createElement.apply(null,n)}m.displayName="MDXCreateElement"},5898:(e,t,n)=>{n.r(t),n.d(t,{assets:()=>l,contentTitle:()=>s,default:()=>c,frontMatter:()=>i,metadata:()=>r,toc:()=>p});var a=n(7462),o=(n(7294),n(3905));const i={author:"Andrey Popp",authorURL:"https://twitter.com/andreypopp",title:"What's new in esy 0.4.x"},s=void 0,r={permalink:"/blog/2018/12/27/0.4.x",source:"@site/blog/2018-12-27-0.4.x.md",title:"What's new in esy 0.4.x",description:"This is the first public blog post on the esy dev blog.  We've been writing",date:"2018-12-27T00:00:00.000Z",formattedDate:"December 27, 2018",tags:[],readingTime:6.395,hasTruncateMarker:!0,authors:[{name:"Andrey Popp",url:"https://twitter.com/andreypopp"}],frontMatter:{author:"Andrey Popp",authorURL:"https://twitter.com/andreypopp",title:"What's new in esy 0.4.x"},prevItem:{title:"New release - 0.6.0 \ud83c\udf89",permalink:"/blog/2020/01/12/0.6.0"}},l={authorsImageUrls:[void 0]},p=[{value:"What Is Esy",id:"what-is-esy",level:2},{value:"esy 0.4.x",id:"esy-04x",level:2},{value:"Plug&#39;n&#39;play Installations",id:"plugnplay-installations",level:3},{value:"Alpha preview of Windows support",id:"alpha-preview-of-windows-support",level:3},{value:"Other 0.4.x goodies",id:"other-04x-goodies",level:3}],u={toc:p},d="wrapper";function c(e){let{components:t,...n}=e;return(0,o.kt)(d,(0,a.Z)({},u,n,{components:t,mdxType:"MDXLayout"}),(0,o.kt)("p",null,"This is the first public blog post on the esy dev blog.  We've been writing\nlots and lots of code to make esy work well, and until now we haven't\ncommunicated much about esy."),(0,o.kt)("h2",{id:"what-is-esy"},"What Is Esy"),(0,o.kt)("p",null,"If you've stumbled upon this and don't know what esy is: esy is a\n\"package.json\"-like workflow with first class support for native development."),(0,o.kt)("p",null,"Esy started as part of the ",(0,o.kt)("a",{parentName:"p",href:"https://reasonml.github.io"},"reason")," effort with the goal of\nimplementing isolated and fast native Reason/OCaml project builds that were\nfamiliar to JavaScript developers. Esy itself is compiled natively,\nand can manage packages for most compiled languages (we use it to\npackage/distribute C/C++ packages in addition to Reason and OCaml)."),(0,o.kt)("p",null,"Esy should be familiar to anyone with experience with Yarn, or npm (just run\n",(0,o.kt)("inlineCode",{parentName:"p"},"esy")," inside a directory with a ",(0,o.kt)("inlineCode",{parentName:"p"},"package.json"),")."),(0,o.kt)("ul",null,(0,o.kt)("li",{parentName:"ul"},(0,o.kt)("p",{parentName:"li"},"esy provides a unified package management workflow that can install/build\npackages from ",(0,o.kt)("a",{parentName:"p",href:"https://opam.ocaml.org/"},"opam")," as well as native packages published to ",(0,o.kt)("a",{parentName:"p",href:"https://npmjs.com/"},"npm"))),(0,o.kt)("li",{parentName:"ul"},(0,o.kt)("p",{parentName:"li"},"esy is not tied to any particular choice of a language/platform. Though we are\nfocusing on native Reason/OCaml first.")),(0,o.kt)("li",{parentName:"ul"},(0,o.kt)("p",{parentName:"li"},"esy is build-system agnostic: you don't have to port a project\nto some specific build system to make it work with esy.")),(0,o.kt)("li",{parentName:"ul"},(0,o.kt)("p",{parentName:"li"},'esy tries to provide "hermetic" builds so that builds of packages are\nunaffected by the system software installed at global paths: if it works on my\nmachine then it should work on yours.')),(0,o.kt)("li",{parentName:"ul"},(0,o.kt)("p",{parentName:"li"},"esy caches built packages across projects: with a warm cache, new projects\nare cheap to initialise and build."))),(0,o.kt)("p",null,"This is not an exhaustive list of esy features but we think these are the most\nimportant points.\nRead more about esy's motivations in the ",(0,o.kt)("a",{parentName:"p",href:"https://esy.sh/docs/en/what-why.html"},"esy docs")," "),(0,o.kt)("h2",{id:"esy-04x"},"esy 0.4.x"),(0,o.kt)("p",null,"We recently promoted the 0.4.9 release of esy as ",(0,o.kt)("inlineCode",{parentName:"p"},"latest"),". That means if you\nexecute:"),(0,o.kt)("pre",null,(0,o.kt)("code",{parentName:"pre",className:"language-shell"},"% npm install -g esy\n")),(0,o.kt)("p",null,"You'll get ",(0,o.kt)("inlineCode",{parentName:"p"},"esy@0.4.9")," which is packed with new features. Below we discuss some\nof those."),(0,o.kt)("h3",{id:"plugnplay-installations"},"Plug'n'play Installations"),(0,o.kt)("p",null,(0,o.kt)("strong",{parentName:"p"},"TL;DR:")," esy won't populate ",(0,o.kt)("inlineCode",{parentName:"p"},"node_modules")," directory with package sources\nanymore, and esy now supports installing Plug'n'play(pnp) JavaScript\ndependencies."),(0,o.kt)("p",null,"In its first iteration, ",(0,o.kt)("inlineCode",{parentName:"p"},"esy")," initially installed all dependency sources into\n",(0,o.kt)("inlineCode",{parentName:"p"},"node_modules.")," The benefit of this is that approach is that it was compatible\nwith popular JS tooling that relied on ",(0,o.kt)("inlineCode",{parentName:"p"},"node_modules")," directory. The downside\nwas that for native packages (the main focus of esy) copying sources over from\ncache to a ",(0,o.kt)("inlineCode",{parentName:"p"},"node_modules")," directory was unnecessary and a waste of time and\ndisk space."),(0,o.kt)("p",null,"Furthermore, esy already builds projects purely out-of-source to ensure\nreproducibility - installing into ",(0,o.kt)("inlineCode",{parentName:"p"},"node_modules")," was merely done to adhere to\nJavaScript's conventions, and it actually risked compromising reproducibility."),(0,o.kt)("p",null,"So how could esy achieve the best of both worlds (JS runtime compatibility) and\n(maintaining reproducible package builds)?"),(0,o.kt)("p",null,"Fortunately, Yarn team figured out how to ditch ",(0,o.kt)("inlineCode",{parentName:"p"},"node_modules")," for JS packages.\nThey designed a new convention called ",(0,o.kt)("a",{parentName:"p",href:"https://github.com/arcanis/rfcs/blob/6fc13d52f43eff45b7b46b707f3115cc63d0ea5f/accepted/0000-plug-an-play.md"},"Plug'n'play installations"),' ("pnp").\nPnp is a way to run JS packages directly from the global package cache without\ncopying them to ',(0,o.kt)("inlineCode",{parentName:"p"},"node_modules"),", while having Node, Webpack and other runtimes\nto be able to resolve code from there."),(0,o.kt)("p",null,"As of 0.4.x, esy now places a copy of Yarn's ",(0,o.kt)("inlineCode",{parentName:"p"},"pnp.js")," runtime at installation\ntime into your project when installing JavaScript dependencies. That ",(0,o.kt)("inlineCode",{parentName:"p"},"pnp.js"),"\nallows ",(0,o.kt)("inlineCode",{parentName:"p"},"node"),"'s module resolution to work even if dependencies are not in\n",(0,o.kt)("inlineCode",{parentName:"p"},"node_modules"),". That makes ",(0,o.kt)("inlineCode",{parentName:"p"},"esy")," JavaScript dependencies more like native\ndependencies ","\u2014"," they don't have to be copied into ",(0,o.kt)("inlineCode",{parentName:"p"},"node_modules"),".  Now,\neven if your project has JavaScript dependencies, installations with a warm\ncache are fast. Like, really fast (timings are for\n",(0,o.kt)("a",{parentName:"p",href:"https://github.com/esy-ocaml/hello-reason"},"esy-ocaml/hello-reason")," project):"),(0,o.kt)("pre",null,(0,o.kt)("code",{parentName:"pre",className:"language-shell"},"% time esy install\ninfo install 0.4.7\ninfo fetching: done\ninfo installing: done\nesy install  0.08s user 0.06s system 93% cpu 0.142 total\n")),(0,o.kt)("p",null,"This also means that esy is now compatible with the most important parts of the\nJS ecosystem: webpack, jest, flow, react-scripts, rollup, prettier and others\nwhich have all been made pnp compatible thanks to the efforts of Yarn. A few\nnpm packages have still not made themselves pnp compatible ","\u2014"," you should\nfile issues on those projects requesting that they support pnp, so that they\ncan be used with Yarn pnp, esy, and any other package manager that adopts\nthe pnp standard."),(0,o.kt)("p",null,"The workflow for working with JS (non-native) packages with esy looks like this:"),(0,o.kt)("ul",null,(0,o.kt)("li",{parentName:"ul"},(0,o.kt)("p",{parentName:"li"},"After installing dependencies as usual, execute pnp-enabled NodeJs\ninterpreter:"),(0,o.kt)("pre",{parentName:"li"},(0,o.kt)("code",{parentName:"pre",className:"language-shell"},"% esy node\n"))),(0,o.kt)("li",{parentName:"ul"},(0,o.kt)("p",{parentName:"li"},"Execute npm binaries installed with packages like webpack, flow, jest and\nsimilar:"),(0,o.kt)("pre",{parentName:"li"},(0,o.kt)("code",{parentName:"pre",className:"language-shell"},"% esy webpack\n% esy flow\n% esy jest\n")))),(0,o.kt)("h3",{id:"alpha-preview-of-windows-support"},"Alpha preview of Windows support"),(0,o.kt)("p",null,"Another huge feature which shipped in 0.4.x is preliminary native Windows\nsupport! Install and use ",(0,o.kt)("inlineCode",{parentName:"p"},"esy")," directly from native Windows command prompt\nwithout needing to install anything else on your system.\nYes ","\u2014"," it produces pure native Windows binaries that run on any Windows\nmachine."),(0,o.kt)("p",null,"Thanks to heroic effots of ",(0,o.kt)("a",{parentName:"p",href:"https://github.com/bryphe"},"Bryan Phelps")," and foundational work by the\nOCaml community developing Reason/OCaml, native project management on Windows\nare now as easy as on macOS/Linux:"),(0,o.kt)("pre",null,(0,o.kt)("code",{parentName:"pre",className:"language-shell"},"C:\\Users\\Andrey> git clone https://github.com/facebook/reason\nC:\\Users\\Andrey> cd reason\nC:\\Users\\Andrey> esy\ninfo install 0.4.9\ninfo fetching: done\ninfo installing: done\n")),(0,o.kt)("p",null,"There is more to say about how Windows support is implemented in esy and we\nwill make sure there's a dedicated post on this in the near future where we\nwill describe some of the foundational compiler and tooling work for Windows\nthat the OCaml community has invested in."),(0,o.kt)("p",null,"Note though that Windows support is still considered alpha ","\u2014"," there are\nrough edges which needs to be fixed. If you are a developer who works on Windows\nand want to help ","\u2014"," jump into ",(0,o.kt)("a",{parentName:"p",href:"https://github.com/esy/esy/issues?q=is%3Aissue+is%3Aopen+label%3Awindows"},'esy/esy issues labelled\n"Windows"')," and help us! The good thing is that we have CI running on\nWindows too (a big thank you to ",(0,o.kt)("a",{parentName:"p",href:"https://github.com/ulrikstrid"},"Ulrik Strid")," for making sure a large\npart of our test suite can run on Windows)."),(0,o.kt)("h3",{id:"other-04x-goodies"},"Other 0.4.x goodies"),(0,o.kt)("p",null,"There are lots and lots of changes in the 0.4.x release line, which could have\narguably been versioned ",(0,o.kt)("inlineCode",{parentName:"p"},"0.5.x"),". In the future, we are aiming for more\nincremental releases."),(0,o.kt)("p",null,"There are too many new features to list, but to highlight a couple of entries\nin the ",(0,o.kt)("a",{parentName:"p",href:"https://github.com/esy/esy/blob/496923fce0412f1e3e81ebfa8797a4e09f28ecd4/CHANGELOG.md#048--latest"},"CHANGELOG"),":"),(0,o.kt)("ul",null,(0,o.kt)("li",{parentName:"ul"},(0,o.kt)("p",{parentName:"li"},"Improved workflow for linked packages: working on multiple packages in\ndevelopment is now more efficient and esy allows more flexibility in how you\norganize your project.")),(0,o.kt)("li",{parentName:"ul"},(0,o.kt)("p",{parentName:"li"},"Support for multiple isolated environments constructed on the fly from\npackage configs. Now you may have multiple ",(0,o.kt)("inlineCode",{parentName:"p"},".json")," configurations in your\nproject root (similar to a monorepo) and install/build them in total\nisolation. If you have a ",(0,o.kt)("inlineCode",{parentName:"p"},"package.dev.json")," file you can use it explicitly:"),(0,o.kt)("pre",{parentName:"li"},(0,o.kt)("code",{parentName:"pre",className:"language-shell"},"% esy @package.dev.json build\n"))),(0,o.kt)("li",{parentName:"ul"},(0,o.kt)("p",{parentName:"li"},"Flexible package override mechanism which allows turning any source code\ndistribution into an esy package, bringing it into your project with all the\nbenefits of the esy workflow: cached builds, isolated environments, etc.\nThis lets you turn any git hash or URL into an esy package without forking\nit, even if that package doesn't have a ",(0,o.kt)("inlineCode",{parentName:"p"},"package.json")," file."),(0,o.kt)("pre",{parentName:"li"},(0,o.kt)("code",{parentName:"pre",className:"language-json"},'{\n  "resolutions": {\n    "pkg-config": {\n      "source": "https://...",\n      "override": {\n        "build": [\n          "./configure --prefix #{self.install}",\n          "make"\n        ],\n        "install": [\n          "make install"\n        ]\n      }\n    }\n  }\n'))),(0,o.kt)("li",{parentName:"ul"},(0,o.kt)("p",{parentName:"li"},"Numerous improvements to esy's user interface: new commands (",(0,o.kt)("inlineCode",{parentName:"p"},"esy show")," and\n",(0,o.kt)("inlineCode",{parentName:"p"},"esy status"),"), faster ",(0,o.kt)("inlineCode",{parentName:"p"},"esy x ..."),' command invocations, a new set of low level\nplumbing commands for "scriptable" esy workflows, ...')),(0,o.kt)("li",{parentName:"ul"},(0,o.kt)("p",{parentName:"li"},"New ",(0,o.kt)("inlineCode",{parentName:"p"},"esy.lock")," format which is easier to review on updates.")),(0,o.kt)("li",{parentName:"ul"},(0,o.kt)("p",{parentName:"li"},"Bug fixes, bug fixes, bug fixes, ..."))),(0,o.kt)("p",null,"Some of these features are not documented yet properly but we'll make sure we do\nthis and then post updates on this blog."),(0,o.kt)("p",null,"Stay tuned!"))}c.isMDXComponent=!0}}]);