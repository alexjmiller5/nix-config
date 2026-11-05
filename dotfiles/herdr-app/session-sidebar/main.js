import { View, div, svg, image } from "gpui-kit";
import { v_flex } from "gpui-base";
import { agents, spaces, panes, machines, hc, run, shared, setShared, theme, home, props, setAgentOrder } from "herdr";

export function groupSidebar(allSpaces, allPanes, sessions, allMachines = []) {
  const agentsByTerminal = new Map(sessions.map(agent => [agent.address, agent]));
  const groups = new Map([["local", []]]);
  for (const machine of allMachines) {
    if (machine.name && !machine.temporary) groups.set(machine.name, []);
  }
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
  else run("space.new", { machine, folder: "" });
}

export default class AgentSidebar extends View {
  init(_props, cx) {
    this.connections = [];
    this.refreshMachines(cx);
    cx.timer.every(15000, cx => this.refreshMachines(cx));
  }

  refreshMachines(cx) {
    if (this.refreshing) return;
    this.refreshing = true;
    cx.spawn(async cx => {
      try {
        const result = await hc(["machine", "ls", "--json"]);
        if (result.code === 0) this.connections = JSON.parse(result.stdout).machines ?? [];
      } finally {
        this.refreshing = false;
        cx.notify();
      }
    });
  }

  render() {
    const t = theme();
    const allSpaces = spaces();
    const sessions = agents();
    const connections = this.connections ?? [];
    const known = [...machines(), ...connections];
    const groups = groupSidebar(allSpaces, panes(), sessions, known);
    setAgentOrder(sessions.map(agent => agent.address));
    return v_flex().relative().size_full().min_h(0)
      .on_mouse_move((event,cx)=>{
        if (!this.drag) return;
        this.drag.pointer=event.local_position;
        this.drag.lifted ||= Math.hypot(event.position.x-this.drag.start.x,event.position.y-this.drag.start.y)>4;
        cx.notify();
      })
      .on_hover((hovered,cx)=>{if (!hovered && this.drag) {this.drag=null;cx.notify();}})
      .child(v_flex().id("agent-sidebar").size_full().min_h(0)
      .on_mouse_up("left",(_event,cx)=>{this.drag=null;cx.notify();})
      .on_mouse_down_out(()=>{this.drag=null;})
      .overflow_y_scrollbar().px(4).py(6).gap(12)
      .children(groups.map(group =>
        v_flex().gap(2)
          .child(div().px(8).pb(3).text_size(11).text_color(t.dim)
            .cursor_pointer().hover(heading => heading.text_color(t.foreground))
            .on_click(() => selectMachine(group.machine, allSpaces)).child(group.machine === "local" ? (props()?.localLabel ?? "Local") : `${group.machine} · ${(connections.find(m => m.name === group.machine)?.state ?? "loading").replace(/_/g, " ")}`))
          .children(group.spaces.map(space =>
            v_flex().gap(1)
              .when(space.named || space.name !== "~", group => group.child(div().id(`space-${space.id}`).px(8).py(3)
                .text_size(11).text_color(space.active ? t.foreground : t.dim)
                .cursor_pointer().hover(row => row.text_color(t.foreground))
                .on_click(() => run("space.select", { id: space.id }))
                .child(div().truncate().child(space.name))))
              .children(space.rows.map(pane =>
                div().id(`terminal-${pane.terminal}`).pl(16).pr(8).py(5).rounded(5).flex().items_center().gap(7)
                  .text_size(12).text_color(pane.focused ? t.foreground : t.muted)
                  .when(pane.focused, row => row.bg(t.hover))
                  .cursor_pointer().hover(row => row.bg(t.hover).text_color(t.foreground))
                  .on_mouse_down("left", (event,cx)=>{
                    this.suppressClick=false;
                    const selected=shared("compact.tabs.selection");
                    const chosen=selected?.space===space.id && selected.ids.includes(pane.tab);
                    if (!chosen) setShared("compact.tabs.selection",null);
                    this.drag={space:space.id,source:pane.tab,ids:chosen ? selected.ids : [pane.tab],name:pane.name,start:event.position};
                    cx.stop_propagation();
                  })
                  .on_hover((hovered,cx)=>{
                    if (hovered && this.drag?.space===space.id) {this.drag.target=pane.tab;cx.notify();}
                  })
                  .when(this.drag?.target===pane.tab && !this.drag.ids.includes(pane.tab),row=>row.border_1().border_color(t.ansi4))
                  .when(this.drag?.lifted && this.drag.ids.includes(pane.tab),row=>row.opacity(0.35))
                  .on_mouse_up("left", (_event,cx)=>{
                    if (this.drag?.space===space.id && !this.drag.ids.includes(pane.tab)) {
                      setShared("compact.tabs.drop",{...this.drag,target:pane.tab});
                      run("compact-terminals-bar.drop");
                      this.suppressClick=true;
                    }
                    this.drag=null;cx.notify();
                  })
                  .on_click(()=>{
                    if (this.suppressClick) {this.suppressClick=false;return;}
                    setShared("compact.tabs.selection",null);
                    run("pane.focus",{pane:pane.pane});
                  })
                  .when(Boolean(pane.program?.agent && pane.program?.icon), row =>
                    row.child(pane.program.tint
                      ? svg(pane.program.icon).size(14).flex_none().text_color(pane.program.color ?? t.muted)
                      : image(pane.program.icon).w(14).h(14).flex_none()))
                  .when(Boolean(pane.status), row => {
                    const color = pane.status === "working" ? t.ansi3 : pane.status === "blocked" ? t.ansi1 : t.ansi2;
                    return row.child(div().size(7).flex_none().rounded_full().border_1().border_color(color)
                      .when(pane.status !== "idle", dot => dot.bg(color)));
                  })
                  .child(div().min_w(0).truncate().child(pane.name))
              ))
          ))
      )))
      .when(this.drag?.lifted && this.drag.pointer, el=>el.child(
        div().id("sidebar-drag-preview").absolute().left(this.drag.pointer.x+10).top(this.drag.pointer.y+12)
          .transition("left",{duration:65,easing:"ease-out"}).transition("top",{duration:65,easing:"ease-out"})
          .w(160).h(34).px(10).flex().items_center().rounded(9).border_1().border_color(t.ansi4)
          .bg(t.hover).shadow_lg().opacity(0.95).text_size(12).text_color(t.foreground)
          .child(div().truncate().child(this.drag.ids.length>1 ? `${this.drag.name} + ${this.drag.ids.length-1}` : this.drag.name))
      ));
  }
}
