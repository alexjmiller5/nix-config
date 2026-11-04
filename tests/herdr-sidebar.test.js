import { expect, mock, test } from "bun:test";
mock.module("gpui-kit", () => ({ View: class {}, div() {} }));
mock.module("gpui-base", () => ({ v_flex() {} }));
const commands = [];
mock.module("herdr", () => ({ agents() {}, machines() {}, hc() {}, panes() {}, spaces() {}, run: (command,args) => commands.push([command,args]), theme() {}, home: () => "/local-home", props: () => ({}), setAgentOrder() {} }));
const { groupSidebar, selectMachine } = await import("../dotfiles/herdr-app/session-sidebar/main.js");

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
