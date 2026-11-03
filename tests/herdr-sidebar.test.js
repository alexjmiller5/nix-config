import { expect, mock, test } from "bun:test";
mock.module("gpui-kit", () => ({ View: class {}, div() {} }));
mock.module("gpui-base", () => ({ v_flex() {} }));
const commands = [];
mock.module("herdr", () => ({ agents() {}, spaces() {}, run: (command,args) => commands.push([command,args]), theme() {}, home: () => "/local-home", props: () => ({}), setAgentOrder() {} }));
const { groupAgents, selectMachine } = await import("../dotfiles/herdr-app/agent-sidebar/main.js");

test("sessions group by their actual machine without dropping or reordering sessions", () => {
  const agents = [
    { address: "mini/t1", space: "remote", tab_name: "First" },
    { address: "t2", space: "local", tab_name: "Local" },
    { address: "mini/t3", space: "remote", tab_name: "Second" },
  ];
  const groups = groupAgents(agents, [{ id: "remote", machine: "mini" }, { id: "local", machine: null }]);
  expect(groups.map(g => [g.machine, g.agents.map(a => a.tab_name)])).toEqual([
    ["local", ["Local"]], ["mini", ["First", "Second"]],
  ]);
  expect(agents.map(a => a.address)).toEqual(["mini/t1", "t2", "mini/t3"]);
});

test("an agent outside the visible spaces still groups by its core address", () => {
  expect(groupAgents([{ address: "other/t1" }], []).map(g => g.machine)).toEqual(["local", "other"]);
  expect(groupAgents([{ address: "t1" }], [])[0].machine).toBe("local");
  expect(groupAgents([], [])).toEqual([{ machine: "local", agents: [] }]);
});

test("laptop stays available without agent sessions and selects its existing shell space", () => {
  const spaces = [{id:"remote",machine:"mini"},{id:"laptop",machine:null}];
  expect(groupAgents([{address:"mini/t1",space:"remote"}],spaces)[0]).toEqual({machine:"local",agents:[]});
  selectMachine("local",spaces);
  expect(commands.at(-1)).toEqual(["space.select",{id:"laptop"}]);
  selectMachine("local",[]);
  expect(commands.at(-1)).toEqual(["space.new",{folder:"/local-home"}]);
});
