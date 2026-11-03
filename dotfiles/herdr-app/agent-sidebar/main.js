import { View, div } from "gpui-kit";
import { v_flex } from "gpui-base";
import { agents, spaces, panes, run, theme, home, props, setAgentOrder } from "herdr";

export function groupSidebar(allSpaces, allPanes, sessions) {
  const agentsByTerminal = new Map(sessions.map(agent => [agent.address, agent]));
  const groups = new Map([["local", []]]);
  for (const space of allSpaces) {
    const machine = space.machine ?? "local";
    if (!groups.has(machine)) groups.set(machine, []);
    const rows = space.tabs.flatMap(tab => allPanes
      .filter(pane => pane.tab === tab.id && pane.terminal)
      .map(pane => ({
        ...pane,
        name: agentsByTerminal.get(pane.terminal)?.tab_name || tab.name || pane.title || "Terminal",
      })));
    groups.get(machine).push({ ...space, rows });
  }
  return [...groups].map(([machine, spaces]) => ({ machine, spaces }));
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
    const sessions = agents();
    const groups = groupSidebar(allSpaces, panes(), sessions);
    setAgentOrder(sessions.map(agent => agent.address));
    return v_flex().id("agent-sidebar").size_full().min_h(0)
      .overflow_y_scrollbar().px(4).py(6).gap(12)
      .children(groups.map(group =>
        v_flex().gap(2)
          .child(div().px(8).pb(3).text_size(11).text_color(t.dim)
            .cursor_pointer().hover(heading => heading.text_color(t.foreground))
            .on_click(() => selectMachine(group.machine, allSpaces)).child(group.machine === "local" ? (props()?.localLabel ?? "Local") : group.machine))
          .children(group.spaces.map(space =>
            v_flex().gap(1)
              .child(div().id(`space-${space.id}`).px(8).py(3)
                .text_size(11).text_color(space.active ? t.foreground : t.dim)
                .cursor_pointer().hover(row => row.text_color(t.foreground))
                .on_click(() => run("space.select", { id: space.id }))
                .child(div().truncate().child(space.name)))
              .children(space.rows.map(pane =>
                div().id(`terminal-${pane.terminal}`).pl(16).pr(8).py(5).rounded(5)
                  .text_size(12).text_color(pane.focused ? t.foreground : t.muted)
                  .when(pane.focused, row => row.bg(t.hover))
                  .cursor_pointer().hover(row => row.bg(t.hover).text_color(t.foreground))
                  .on_click(() => run("pane.focus", { pane: pane.pane }))
                  .child(div().truncate().child(pane.name))
              ))
          ))
      ));
  }
}
