import { expect, mock, test } from "bun:test";
mock.module("gpui-kit", () => ({ View: class {}, div() {}, svg() {}, image() {} }));
mock.module("gpui-base", () => ({ v_flex() {}, h_flex() {} }));
const commands = [];
mock.module("herdr", () => ({ agents() {}, machines() {}, hc() {}, panes() {}, spaces() {}, run: (command,args) => commands.push([command,args]), theme() {}, home: () => "/local-home", props: () => ({}), setAgentOrder() {}, nextCommand() {}, exec() {}, notify() {}, openOverlay() {}, window() {}, shared() {}, setShared() {} }));
const { previewPosition, insertionSlot, groupSidebar, selectMachine } = await import("../dotfiles/herdr-app/session-sidebar/main.js");

test("all spaces and shell panes remain visible under their actual machine", () => {
  const spaces = [
    {id:"r1",machine:"mini",name:"API",tabs:[{id:"tab1",name:"Server"}]},
    {id:"r2",machine:"mini",name:"Web",tabs:[{id:"tab2",name:"Build"}]},
    {id:"l",machine:null,name:"Home",tabs:[]},
  ];
  const panes = [
    {pane:"p1",terminal:"mini/t1",tab:"tab1",title:"zsh"},
    {pane:"p2",terminal:"mini/t2",tab:"tab2",title:"Agent"},
    {pane:"p3",terminal:null,tab:"tab1",title:"Files"},
  ];
  const groups = groupSidebar(spaces,panes,[{address:"mini/t2",tab_name:"Fix Login"}]);
  expect(groups.map(g=>[g.machine,g.spaces.map(s=>s.name)])).toEqual([
    ["local",["Home"]],["mini",["API","Web"]]
  ]);
  expect(groups[1].spaces.map(s=>s.rows.map(r=>[r.terminal,r.name]))).toEqual([
    [["mini/t1","Server"]],[["mini/t2","Fix Login"]]
  ]);
  expect(panes).toHaveLength(3);
});

test("split shells each appear and local machine remains with no spaces", () => {
  expect(groupSidebar([],[],[])).toEqual([{machine:"local",spaces:[]}]);
  const groups=groupSidebar([{id:"s",machine:null,tabs:[{id:"t",name:"Shell"}]}],[
    {pane:"p1",terminal:"t1",tab:"t"},{pane:"p2",terminal:"t2",tab:"t"}
  ],[]);
  expect(groups[0].spaces[0].rows.map(r=>r.terminal)).toEqual(["t1","t2"]);
});

test("machine navigation selects an existing space or starts local shell", () => {
  selectMachine("local",[{id:"laptop",machine:null}]);
  expect(commands.at(-1)).toEqual(["space.select",{id:"laptop"}]);
  selectMachine("local",[]);
  expect(commands.at(-1)).toEqual(["space.new",{folder:"/local-home"}]);
});

test("connected machines remain visible without spaces and can open a space", () => {
  expect(groupSidebar([],[],[],[{name:null},{name:"mini",state:"disconnected"}]).map(g=>g.machine)).toEqual(["local","mini"]);
  selectMachine("mini",[]);
  expect(commands.at(-1)).toEqual(["space.new",{machine:"mini",folder:""}]);
});

test("drag preview is centered on the pointer and stays inside its panel",()=>{
 expect(previewPosition({x:200,y:100},{width:500,height:300})).toEqual({x:120,y:83});
 expect(previewPosition({x:2,y:2},{width:500,height:300})).toEqual({x:8,y:8});
 expect(previewPosition({x:499,y:299},{width:500,height:300})).toEqual({x:332,y:258});
});
test("hovering each half inserts before or after the row, including skipping rows",()=>{
 expect(insertionSlot([30,30,30],30,0,3,41)).toBe(1);
 expect(insertionSlot([30,30,30],30,0,3,49)).toBe(2);
 expect(insertionSlot([30,30,30],30,0,0,71)).toBe(1);
 expect(insertionSlot([30,30,30],30,0,0,79)).toBe(2);
});
