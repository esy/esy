"use strict";(self.webpackChunksite_v_3=self.webpackChunksite_v_3||[]).push([[4195],{9454:(e,n,t)=>{t.r(n),t.d(n,{default:()=>g});var r=t(7294),a=t(6010),i=t(9960),l=t(2263),o=t(2949),c=t(7452);t(614);function s(e,n){var t="function"==typeof Symbol&&e[Symbol.iterator];if(!t)return e;var r,a,i=t.call(e),l=[];try{for(;(void 0===n||n-- >0)&&!(r=i.next()).done;)l.push(r.value)}catch(e){a={error:e}}finally{try{r&&!r.done&&(t=i.return)&&t.call(i)}finally{if(a)throw a.error}}return l}var m,u=function(e){var n=e.children;return r.createElement("div",{className:"react-terminal-line"},n)};!function(e,n){void 0===n&&(n={});var t=n.insertAt;if(e&&"undefined"!=typeof document){var r=document.head||document.getElementsByTagName("head")[0],a=document.createElement("style");a.type="text/css","top"===t&&r.firstChild?r.insertBefore(a,r.firstChild):r.appendChild(a),a.styleSheet?a.styleSheet.cssText=e:a.appendChild(document.createTextNode(e))}}("/**\n * Modfied version of [termynal.js](https://github.com/ines/termynal/blob/master/termynal.css).\n *\n * @author Ines Montani <ines@ines.io>\n * @version 0.0.1\n * @license MIT\n */\n .react-terminal-wrapper {\n  width: 100%;\n  background: #252a33;\n  color: #eee;\n  font-size: 18px;\n  font-family: 'Fira Mono', Consolas, Menlo, Monaco, 'Courier New', Courier, monospace;\n  border-radius: 4px;\n  padding: 75px 45px 35px;\n  position: relative;\n  -webkit-box-sizing: border-box;\n          box-sizing: border-box;\n }\n\n.react-terminal {\n  overflow: auto;\n  display: flex;\n  flex-direction: column;\n}\n\n.react-terminal-wrapper.react-terminal-light {\n  background: #ddd;\n  color: #1a1e24;\n}\n\n.react-terminal-window-buttons {\n  position: absolute;\n  top: 15px;\n  left: 15px;\n  display: flex;\n  flex-direction: row;\n  gap: 10px;\n}\n\n.react-terminal-window-buttons button {\n  width: 15px;\n  height: 15px;\n  border-radius: 50%;\n  border: 0;\n}\n\n.react-terminal-window-buttons button.clickable {\n  cursor: pointer;\n}\n\n.react-terminal-window-buttons button.red-btn {\n  background: #d9515d;\n}\n\n.react-terminal-window-buttons button.yellow-btn {\n  background: #f4c025;\n}\n\n.react-terminal-window-buttons button.green-btn {\n  background: #3ec930;\n}\n\n.react-terminal-wrapper:after {\n  content: attr(data-terminal-name);\n  position: absolute;\n  color: #a2a2a2;\n  top: 5px;\n  left: 0;\n  width: 100%;\n  text-align: center;\n  pointer-events: none;\n}\n\n.react-terminal-wrapper.react-terminal-light:after {\n  color: #D76D77;\n}\n\n.react-terminal-line {\n  white-space: pre;\n}\n\n.react-terminal-line:before {\n  /* Set up defaults and ensure empty lines are displayed. */\n  content: '';\n  display: inline-block;\n  vertical-align: middle;\n  color: #a2a2a2;\n}\n\n.react-terminal-light .react-terminal-line:before {\n  color: #D76D77;\n}\n\n.react-terminal-input:before {\n  margin-right: 0.75em;\n  content: '$';\n}\n\n.react-terminal-input[data-terminal-prompt]:before {\n  content: attr(data-terminal-prompt);\n}\n\n.react-terminal-wrapper:focus-within .react-terminal-active-input .cursor {\n  position: relative;\n  display: inline-block;\n  width: 0.55em;\n  height: 1em;\n  top: 0.225em;\n  background: #fff;\n  -webkit-animation: blink 1s infinite;\n          animation: blink 1s infinite;\n}\n\n/* Cursor animation */\n\n@-webkit-keyframes blink {\n  50% {\n      opacity: 0;\n  }\n}\n\n@keyframes blink {\n  50% {\n      opacity: 0;\n  }\n}\n\n.terminal-hidden-input {\n    position: fixed;\n    left: -1000px;\n}\n\n/* .react-terminal-progress {\n  display: flex;\n  margin: .5rem 0;\n}\n\n.react-terminal-progress-bar {\n  background-color: #fff;\n  border-radius: .25rem;\n  width: 25%;\n}\n\n.react-terminal-wrapper.react-terminal-light .react-terminal-progress-bar {\n  background-color: #000;\n} */\n"),function(e){e[e.Light=0]="Light",e[e.Dark=1]="Dark"}(m||(m={}));var d=function(e){var n=e.name,t=e.prompt,a=e.height,i=void 0===a?"600px":a,l=e.colorMode,o=e.onInput,c=e.children,u=e.startingInputValue,d=void 0===u?"":u,p=e.redBtnCallback,f=e.yellowBtnCallback,b=e.greenBtnCallback,h=s((0,r.useState)(""),2),g=h[0],y=h[1],v=s((0,r.useState)(0),2),w=v[0],k=v[1],E=(0,r.useRef)(null);(0,r.useEffect)((function(){y(d.trim())}),[d]);var x=(0,r.useRef)(!1);(0,r.useEffect)((function(){x.current&&setTimeout((function(){var e;return null===(e=null==E?void 0:E.current)||void 0===e?void 0:e.scrollIntoView({behavior:"auto",block:"nearest"})}),500),x.current=!0}),[c]),(0,r.useEffect)((function(){var e,n;if(null!=o){var t=[],r=function(e){var n=function(){var n;return null===(n=null==e?void 0:e.querySelector(".terminal-hidden-input"))||void 0===n?void 0:n.focus()};null==e||e.addEventListener("click",n),t.push({terminalEl:e,listener:n})};try{for(var a=function(e){var n="function"==typeof Symbol&&Symbol.iterator,t=n&&e[n],r=0;if(t)return t.call(e);if(e&&"number"==typeof e.length)return{next:function(){return e&&r>=e.length&&(e=void 0),{value:e&&e[r++],done:!e}}};throw new TypeError(n?"Object is not iterable.":"Symbol.iterator is not defined.")}(document.getElementsByClassName("react-terminal-wrapper")),i=a.next();!i.done;i=a.next())r(i.value)}catch(n){e={error:n}}finally{try{i&&!i.done&&(n=a.return)&&n.call(a)}finally{if(e)throw e.error}}return function(){t.forEach((function(e){e.terminalEl.removeEventListener("click",e.listener)}))}}}),[o]);var C=["react-terminal-wrapper"];return l===m.Light&&C.push("react-terminal-light"),r.createElement("div",{className:C.join(" "),"data-terminal-name":n},r.createElement("div",{className:"react-terminal-window-buttons"},r.createElement("button",{className:(f?"clickable":"")+" red-btn",disabled:!p,onClick:p}),r.createElement("button",{className:(f?"clickable":"")+" yellow-btn",disabled:!f,onClick:f}),r.createElement("button",{className:(b?"clickable":"")+" green-btn",disabled:!b,onClick:b})),r.createElement("div",{className:"react-terminal",style:{height:i}},c,o&&r.createElement("div",{className:"react-terminal-line react-terminal-input react-terminal-active-input","data-terminal-prompt":t||"$",key:"terminal-line-prompt"},g,r.createElement("span",{className:"cursor",style:{left:w+1+"px"}})),r.createElement("div",{ref:E})),r.createElement("input",{className:"terminal-hidden-input",placeholder:"Terminal Hidden Input",value:g,autoFocus:null!=o,onChange:function(e){y(e.target.value)},onKeyDown:function(e){var n,t;if(o)if("Enter"===e.key)o(g),k(0),y("");else if(["ArrowLeft","ArrowRight","ArrowDown","ArrowUp","Delete"].includes(e.key)){var r=e.currentTarget,a="",i=g.length-(r.selectionStart||0);0,i=(n=i)>(t=g.length)?t:n<0?0:n,"ArrowLeft"===e.key?(i>g.length-1&&i--,a=g.slice(g.length-1-i)):"ArrowRight"===e.key||"Delete"===e.key?a=g.slice(g.length-i+1):"ArrowUp"===e.key&&(a=g.slice(0));var l=function(e,n){var t=document.createElement("span");t.style.visibility="hidden",t.style.position="absolute",t.style.fontSize=window.getComputedStyle(e).fontSize,t.style.fontFamily=window.getComputedStyle(e).fontFamily,t.innerText=n,document.body.appendChild(t);var r=t.getBoundingClientRect().width;return document.body.removeChild(t),-r}(r,a);k(l)}}}))};const p={heroBanner:"heroBanner_qdFl",title:"title_GqtP",minHeight:"minHeight_CCu3"},f=function(e){void 0===e&&(e={});const{colorMode:n}=(0,o.I)();return r.createElement(d,{name:"Getting started with esy",colorMode:"light"===n?m.Light:m.Dark,height:"180px"},e.lines.map(((e,n)=>r.createElement(u,{key:n},e))))},b="npm install -g esy\n\n# Clone example, install dependencies, then build\ngit clone https://github.com/esy-ocaml/hello-reason.git\ncd hello-reason\nesy";function h(){const{siteConfig:e}=(0,l.Z)();return r.createElement("main",{className:(0,a.Z)("container",p.heroBanner)},r.createElement("section",{className:"row"},r.createElement("section",{className:(0,a.Z)("col col--6",p.title)},r.createElement("h1",{className:"hero__title"},e.title),r.createElement("p",{className:"hero__subtitle"},e.tagline),r.createElement(i.Z,{className:(0,a.Z)(p.buttons,"button button--secondary button--lg"),to:"/docs/getting-started"},"Get Started")),r.createElement("section",{className:"padding--lg col col--6"},r.createElement(f,{lines:b.split("\n")}))))}function g(){const{siteConfig:e}=(0,l.Z)();return r.createElement(c.Z,{title:`Documentation | ${e.title}`,description:"Package manager for Reason, OCaml and more",wrapperClassName:p.minHeight},r.createElement(h,null))}}}]);