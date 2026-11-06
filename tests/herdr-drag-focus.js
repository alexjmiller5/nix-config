import { mock } from "bun:test";
import assert from "node:assert/strict";

const nodes = [], commands = [], state = new Map();
function element() {
  const data = { handlers: {} };
  const node = new Proxy(data, { get(target, key) {
    if (key in target) return target[key];
    return (...args) => {
      if (key === "id") target.id = args[0];
      if (key === "when" && args[0]) args[1](node);
      if (key === "on_mouse_down") target.handlers[`down-${args[0]}`] = args[1];
      if (key === "on_click") target.handlers.click = args[0];
      if (key === "on_mouse_up") target.handlers[`up-${args[0]}`] = args[1];
      return node;
    };
  }});
  nodes.push(node);
  return node;
}
const space = {id:"s",name:"Home",machine:null,active:true,tabs:[
  {id:"a",name:"Active",active:true},{id:"b",name:"Background",active:false},
]};
const paneList = space.tabs.map(tab=>({pane:`p-${tab.id}`,tab:tab.id,terminal:`t-${tab.id}`,focused:tab.active}));
mock.module("gpui-kit",()=>({View:class {},div:element,svg:element,image:element}));
mock.module("gpui-base",()=>({h_flex:element,v_flex:element}));
mock.module("herdr",()=>({spaces:()=>[space],panes:()=>paneList,agents:()=>[],machines:()=>[],
  run:(name,args)=>commands.push([name,args]),theme:()=>({}),window:()=>({}),
  shared:key=>state.get(key),setShared:(key,value)=>state.set(key,value),
  openOverlay(){},nextCommand(){},hc(){},notify(){},home:()=>"/fixture",props:()=>({}),setAgentOrder(){},
}));
const {default:Bar}=await import("../dotfiles/herdr-app/compact-terminals-bar/main.js");
const {default:Sidebar}=await import("../dotfiles/herdr-app/session-sidebar/main.js");
const event={position:{x:100,y:100},bounds:{x:0,y:0,width:100,height:30},modifiers:{shift:false}};
const cx={stop_propagation(){},notify(){}};
for (const [Type,id,select] of [[Bar,"tm-b","tab.select"],[Sidebar,"terminal-t-b","pane.focus"]]) {
  nodes.length=0;commands.length=0;state.clear();
  const view=new Type();view.widths={};view.render();
  const row=nodes.find(n=>n.id===id);
  assert.ok(row,"background tab renders");
  row.handlers["down-left"](event,cx);
  assert.ok(view.drag,"press prepares a drag");
  assert.equal(commands.length,0,"pressing a background tab does not switch sessions");
  view.drag.lifted=true;view.drag.valid=true;
  nodes.find(n=>n.handlers["up-left"]).handlers["up-left"](event,cx);
  row.handlers.click(event,cx);
  assert.ok(!commands.some(([name])=>name===select),"drag release does not select its source");
  commands.length=0;
  row.handlers["down-left"](event,cx);
  row.handlers.click(event,cx);
  assert.equal(commands.at(-1)[0],select,"a regular click still selects its tab");
}
console.log("Drag preserves focus in both bars; regular clicks still select");
