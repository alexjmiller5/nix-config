import { View, div, svg, image } from "gpui-kit";
import { v_flex } from "gpui-base";
import { agents, spaces, panes, machines, hc, run, openOverlay, shared, setShared, theme, home, props, setAgentOrder } from "herdr";

export function previewPosition(pointer, bounds) {
  const marginY=Math.min(8,Math.max(0,(bounds.height-34)/2));
  return {
    x:Math.max(8,Math.min(pointer.x-80,bounds.width-168)),
    y:Math.max(marginY,Math.min(pointer.y-17,bounds.height-34-marginY)),
  };
}

export function insertionSlot(sizes, gap, spacing, current, pointer) {
  let at=0, next=current;
  sizes.forEach((size,i)=>{
    if (i===current) at+=gap+spacing;
    const center=at+size/2;
    if (i<current && pointer<center && next===current) next=i;
    if (i>=current && pointer>center) next=i+1;
    at+=size+spacing;
  });
  return next;
}

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

  dragRows(space) {
    if(!this.drag?.lifted || this.drag.valid===false || this.drag.space!==space.id) return space.rows;
    const tabs=space.tabs.filter(t=>!this.drag.ids.includes(t.id));
    tabs.splice(this.drag.index,0,{gap:true});
    return tabs.flatMap(tab=>tab.gap ? [{gap:true}] : space.rows.filter(row=>row.tab===tab.id));
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
        this.drag.bounds=event.bounds;
        this.drag.lifted ||= Math.hypot(event.position.x-this.drag.start.x,event.position.y-this.drag.start.y)>4;
        this.drag.valid=event.position.y>=this.drag.origin && event.position.y<=this.drag.origin+this.drag.total;
        if(this.drag.lifted && this.drag.valid) this.drag.index=insertionSlot(this.drag.sizes,this.drag.gap,1,this.drag.index,event.position.y-this.drag.origin);
        cx.notify();
      })
      .on_hover((hovered,cx)=>{if (!hovered && this.drag) {this.drag=null;cx.notify();}})
      .child(v_flex().id("agent-sidebar").size_full().min_h(0)
      .on_mouse_up("left",(_event,cx)=>{
        if(this.drag?.lifted && this.drag.valid!==false){
          setShared("compact.tabs.drop",this.drag);run("compact-terminals-bar.drop");this.suppressClick=true;
        }
        this.drag=null;cx.notify();
      })
      .on_mouse_down_out(()=>{this.drag=null;})
      .on_scroll_wheel((_event,cx)=>{if(this.drag){this.drag=null;this.suppressClick=true;cx.notify();}})
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
              .children(this.dragRows(space).map(pane =>
                pane.gap ? div().id(`sidebar-insertion-slot-${space.id}`).h(this.drag.gap).w_full().flex_none()
                  .rounded(5).border_1().border_color(t.ansi4).bg(t.hover)
                : div().id(`terminal-${pane.terminal}`).pl(16).pr(8).py(5).rounded(5).flex().items_center().gap(7)
                  .text_size(12).text_color(pane.focused ? t.foreground : t.muted)
                  .when(pane.focused, row => row.bg(t.hover))
                  .cursor_pointer().hover(row => row.bg(t.hover).text_color(t.foreground))
                  .on_mouse_down("left", (event,cx)=>{
                    this.suppressClick=false;
                    const selected=shared("compact.tabs.selection");
                    const chosen=selected?.space===space.id && selected.ids.includes(pane.tab);
                    if (!chosen) {
                      setShared("compact.tabs.selection",null);
                      run("pane.focus",{pane:pane.pane});
                    }
                    const ids=space.tabs.map(t=>t.id), moving=chosen ? ids.filter(id=>selected.ids.includes(id)) : [pane.tab];
                    const rowHeight=event.bounds.height;
                    const height=id=>{const count=space.rows.filter(row=>row.tab===id).length;return Math.max(0,count*(rowHeight+1)-1);};
                    const origin=event.bounds.y-space.rows.findIndex(row=>row.pane===pane.pane)*(rowHeight+1);
                    this.drag={space:space.id,source:pane.tab,ids:moving,name:pane.name,start:event.position,origin,
                      sizes:ids.filter(id=>!moving.includes(id)).map(height),
                      total:ids.reduce((n,id)=>n+height(id),0)+ids.length-1,
                      gap:moving.reduce((n,id)=>n+height(id),0)+moving.length-1,
                      index:ids.slice(0,ids.findIndex(id=>moving.includes(id))).filter(id=>!moving.includes(id)).length};
                    cx.stop_propagation();
                  })
                  .on_mouse_down("right", (_event,cx)=>{
                    cx.stop_propagation();
                    this.drag=null;
                    openOverlay({mod:"menu",kind:"popup",width:200,props:{tab:"tab",target:{id:pane.tab,space:space.id}}});
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
        div().id("sidebar-drag-preview").absolute().left(previewPosition(this.drag.pointer,this.drag.bounds).x).top(previewPosition(this.drag.pointer,this.drag.bounds).y)
          
          .w(160).h(34).px(10).flex().items_center().rounded(9).border_1().border_color(this.drag.valid===false ? t.ansi1 : t.ansi4)
          .bg(t.hover).shadow_lg().opacity(0.95).text_size(12).text_color(t.foreground)
          .child(div().truncate().child(this.drag.ids.length>1 ? `${this.drag.name} + ${this.drag.ids.length-1}` : this.drag.name))
      ));
  }
}
