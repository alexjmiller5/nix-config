import { View, div } from "gpui-kit";
import { v_flex } from "gpui-base";
import { agents, spaces, run, theme, home, props, setAgentOrder } from "herdr";

export function groupAgents(sessions, allSpaces) {
  const machines = new Map(allSpaces.map(space => [space.id, space.machine]));
  const groups = new Map([["local", []]]);
  for (const agent of sessions) {
    const machine = machines.get(agent.space)
      ?? (agent.address.includes("/") ? agent.address.split("/")[0] : "local");
    if (!groups.has(machine)) groups.set(machine, []);
    groups.get(machine).push(agent);
  }
  return [...groups].map(([machine, agents]) => ({ machine, agents }));
}

export function selectMachine(machine, allSpaces) {
  const space = allSpaces.find(space => (space.machine ?? "local") === machine);
  if (space) run("space.select", { id: space.id });
  else if (machine === "local") run("space.new", { folder: home() });
}

export default class AgentSidebar extends View {
  render() {
    const t = theme();
    const allSpaces = spaces();
    const groups = groupAgents(agents(), allSpaces);
    setAgentOrder(groups.flatMap(group => group.agents.map(agent => agent.address)));
    return v_flex().id("agent-sidebar").size_full().min_h(0)
      .overflow_y_scrollbar().px(4).py(6).gap(12)
      .children(groups.map(group =>
        v_flex().gap(2)
          .child(div().px(8).pb(3).text_size(11).text_color(t.dim)
            .cursor_pointer().hover(heading => heading.text_color(t.foreground))
            .on_click(() => selectMachine(group.machine, allSpaces)).child(group.machine === "local" ? (props()?.localLabel ?? "Local") : group.machine))
          .children(group.agents.map(agent =>
            div().id(`agent-${agent.address}`).px(8).py(5).rounded(5)
              .text_size(12).text_color(agent.focused ? t.foreground : t.muted)
              .when(agent.focused, row => row.bg(t.hover))
              .cursor_pointer().hover(row => row.bg(t.hover).text_color(t.foreground))
              .on_click(() => run("agent.focus", { terminal: agent.address }))
              .child(div().truncate().child(agent.tab_name || agent.title || "Untitled session"))
          ))
      ));
  }
}
