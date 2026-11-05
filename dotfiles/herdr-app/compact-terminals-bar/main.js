// Terminals tab bar with intrinsic title widths and horizontal overflow.

import { View, div, svg, image } from "gpui-kit";
import { h_flex } from "gpui-base";
import { spaces, panes, run, theme, openOverlay, nextCommand, hc, notify, shared, setShared, window as win } from "herdr";

export function clickSelection(ids, anchor, clicked, shift) {
  if (!shift) return { anchor: clicked, selected: [] };
  const start = ids.includes(anchor) ? anchor : clicked;
  const a = ids.indexOf(start), b = ids.indexOf(clicked);
  return { anchor: start, selected: ids.slice(Math.min(a,b), Math.max(a,b)+1) };
}

export function moveTabOrder(ids, selected, direction) {
  const result = [...ids], chosen = new Set(selected);
  const positions = direction < 0 ? ids.map((_,i)=>i) : ids.map((_,i)=>i).reverse();
  for (const i of positions) {
    const j = i + direction;
    if (j >= 0 && j < result.length && chosen.has(result[i]) && !chosen.has(result[j]))
      [result[i], result[j]] = [result[j], result[i]];
  }
  return result;
}

export function dropTabOrder(ids, selected, target) {
  const moving = ids.filter(id => selected.includes(id));
  if (!moving.length || moving.includes(target) || !ids.includes(target)) return [...ids];
  const rest = ids.filter(id => !moving.includes(id));
  const index = rest.indexOf(target) + (ids.indexOf(moving[0]) < ids.indexOf(target) ? 1 : 0);
  rest.splice(index, 0, ...moving);
  return rest;
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

export function insertTabOrder(ids, selected, index) {
  const moving=ids.filter(id=>selected.includes(id));
  const rest=ids.filter(id=>!moving.includes(id));
  rest.splice(Math.max(0,Math.min(index,rest.length)),0,...moving);
  return rest;
}

const C = {
  tray: "#1d1f22",
  // The shown tab stands out; a hovered one only hints, so the two never look alike.
  tab: "#34373c",
  tabEdge: "#4a4d53",
  hover: "#ffffff07",
  edge: "#383b40",
  chip: "#252628",
  text: "#e8e9eb",
  dim: "#8b8f95",
};

// The pane a tab's tab speaks for: the focused one, else its agent, else the first.
function lead(all, id) {
  const mine = all.filter((p) => p.tab === id);
  return mine.find((p) => p.focused) ?? mine.find((p) => p.program?.agent) ?? mine[0];
}

// The program's tile from the app's table: its color, its glyph (or logo) on it.
function tile(p) {
  const g = p?.program;
  return div()
    .relative()
    .flex_none()
    .w(26)
    .h(26)
    .rounded(7)
    .border_1()
    .border_color("#ffffff14")
    .bg(g?.tile ?? C.chip)
    .flex()
    .items_center()
    .justify_center()
    .when(Boolean(g?.icon), (el) =>
      el.child(g.tint ? svg(g.icon).size(15).text_color(g.color ?? C.text) : image(g.icon).w(15).h(15)),
    );
}

// A control in the draggable bar: the press is its own, not the window's
// (a right press there would open the system's window menu).
function own(el) {
  return el.on_mouse_down("left", (_e, cx) => cx.stop_propagation()).on_mouse_down("right", (_e, cx) => cx.stop_propagation());
}

function windowButton(id, icon, command) {
  return own(
    div()
      .id(id)
      .flex_none()
      .w(24)
      .h(24)
      .rounded_full()
      .flex()
      .items_center()
      .justify_center()
      .bg(C.chip)
      .text_color(C.dim)
      .cursor_pointer()
      .hover((s) => s.bg(C.edge).text_color(C.text))
      .on_click(() => run(command))
      .child(svg(`mods/terminals-bar/${icon}.svg`).size(14)),
  );
}

function iconButton(id, icon, onClick) {
  return own(div())
    .id(id)
    .flex_none()
    .p(7)
    .rounded(8)
    .text_color(C.dim)
    .cursor_pointer()
    .hover((s) => s.bg(C.chip).text_color(C.text))
    .on_click(onClick)
    .child(svg(`mods/terminals-bar/${icon}.svg`).size(17));
}

export default class TerminalsBar extends View {
  init(_props, cx) {
    this.selected = [];
    this.widths = {};
    setShared("compact.tabs.selection", null);
    cx.spawn(async cx => {
      for (;;) {
        const command = await nextCommand();
        if (command === "close") this.closeSelected(cx);
        if (command === "drop") {
          const drop = shared("compact.tabs.drop");
          setShared("compact.tabs.drop", null);
          if (drop) this.dropTabs(drop);
        }
      }
    });
  }

  closeSelected(cx) {
    if (this.busy) return;
    const space = spaces().find(s => s.active);
    if (!space) return;
    const selected = this.spaceId === space.id ? (this.selected ?? []) : [];
    const ids = space.tabs.filter(t => selected.includes(t.id)).map(t => t.id);
    if (!ids.length) ids.push(space.tabs.find(t => t.active)?.id);
    if (!ids[0]) return;
    this.busy = true;
    cx.spawn(async cx => {
      try {
        const launch = await hc(["run", "--bg", "--no-parent", "--no-notify", "--", "herdr-native", "close-group", "--tabs", ...ids]);
        if (launch.code !== 0) throw new Error(launch.stderr || "Could not start group close");
        const job = JSON.parse(launch.stdout).address;
        let record;
        do {
          await hc(["wait", job, "--timeout", "15"]);
          const result = await hc(["get", job]);
          if (result.code !== 0) throw new Error(result.stderr || "Group close status unavailable");
          record = JSON.parse(result.stdout);
        } while (record.state === "live");
        let error;
        if (record.exit_code !== 0) {
          const output = await hc(["read", "--json", job]);
          error = (output.code === 0 ? JSON.parse(output.stdout).text : "") || "Could not close selected tabs";
        }
        await hc(["rm", job]);
        if (error) throw new Error(error);
        this.selected = [];
        setShared("compact.tabs.selection", null);
      } catch (error) {
        notify({title: "Tabs left open", body: String(error)});
      } finally { this.busy = false; cx.notify(); }
    });
  }

  applyOrder(ids, target) {
    const current = [...ids];
    target.forEach((id,i) => {
      if (current[i] === id) return;
      run("tab.move", {id,index:i+1});
      current.splice(current.indexOf(id),1);
      current.splice(i,0,id);
    });
  }

  dropTabs(drop) {
    if (this.busy) return;
    const space = spaces().find(s => s.id === drop.space);
    if (!space) return;
    const ids = space.tabs.map(t => t.id);
    this.applyOrder(ids, drop.index === undefined ? dropTabOrder(ids,drop.ids,drop.target) : insertTabOrder(ids,drop.ids,drop.index));
  }

  moveSelected(direction) {
    if (this.busy) return;
    const space = spaces().find(s => s.active);
    if (!space) return;
    const ids = space.tabs.map(t => t.id);
    const target = moveTabOrder(ids, this.selected ?? [], direction);
    if (target.every((id,i)=>id === ids[i])) return;
    this.applyOrder(ids, target);
  }

  render() {
    const t = theme();
    const space = spaces().find((p) => p.active);
    if (!space) return div();
    const ids = space.tabs.map(t => t.id);
    if (this.spaceId !== space.id) {
      this.spaceId = space.id;
      this.selected = [];
      this.anchor = space.tabs.find(t => t.active)?.id;
      setShared("compact.tabs.selection", null);
    }
    const selection = shared("compact.tabs.selection");
    this.selected = selection?.space === space.id ? selection.ids.filter(id => ids.includes(id)) : [];
    if (selection?.space === space.id) this.anchor = selection.anchor;
    const all = panes();
    const w = win() ?? {};

    const tab = (c) => {
      if (c.gap) return div().id("top-insertion-slot").w(c.width).h_full().flex_none().rounded(10)
        .border_1().border_color("#86b4cb").bg("#86b4cb16");
      const p = lead(all, c.id);
      return own(h_flex())
        .id(`tm-${c.id}`)
        .on_size_change((size,cx)=>{if(this.widths[c.id]!==size.width){this.widths[c.id]=size.width;cx.notify();}})
        .flex_none()
        .min_w(0)
        .h_full()
        .pl(5)
        .pr(12)
        .gap(9)
        .items_center()
        .rounded(13)
        .border_1()
        .cursor_pointer()
        .text_size(13)
        .when(c.active, (el) => el.bg(C.tab).border_color(C.tabEdge))
        .when(this.selected.includes(c.id), el => el.bg("#345565").border_color("#86b4cb"))
        .when(!c.active && !this.selected.includes(c.id), (el) => el.border_color("#00000000").hover((s) => s.bg(C.hover)))
        .on_click((event, cx) => {
          if (this.suppressClick) { this.suppressClick = false; return; }
          const selection = clickSelection(ids, this.anchor, c.id, event.modifiers.shift);
          this.anchor = selection.anchor;
          this.selected = selection.selected;
          setShared("compact.tabs.selection", {space:space.id,ids:this.selected,anchor:this.anchor});
          run("tab.select", { id: c.id });
          cx.notify();
        })
        .on_mouse_down("left", (event, cx) => {
          cx.stop_propagation();
          this.suppressClick = false;
          const chosen = this.selected.includes(c.id);
          if (!chosen && !event.modifiers.shift) {
            this.selected=[];
            this.anchor=c.id;
            setShared("compact.tabs.selection",null);
            run("tab.select",{id:c.id});
          }
          const moving=chosen ? [...this.selected] : [c.id];
          const width=id=>this.widths[id] ?? (id===c.id ? event.bounds.width : 100);
          const origin=event.bounds.x-ids.slice(0,ids.indexOf(c.id)).reduce((n,id)=>n+width(id)+3,0);
          this.drag = {space:space.id,ids:moving,source:c.id,name:c.name,start:event.position,origin,
            sizes:ids.filter(id=>!moving.includes(id)).map(width),
            gap:moving.reduce((n,id)=>n+width(id),0)+3*(moving.length-1),
            index:ids.slice(0,ids.findIndex(id=>moving.includes(id))).filter(id=>!moving.includes(id)).length};
        })
        .on_mouse_down("right", () =>
          openOverlay({ mod: "menu", kind: "popup", width: 200, props: { tab: "tab", target: { id: c.id, space: space.id } } }),
        )
        .child(tile(p))
        .when(Boolean(c.status), el=>{
          const color=c.status === "working" ? t.ansi3 : c.status === "blocked" ? t.ansi1 : t.ansi2;
          return el.child(div().size(7).flex_none().rounded_full().border_1().border_color(color)
            .when(c.status !== "idle", dot=>dot.bg(color)));
        })
        .child(
          h_flex()
            .min_w(0)
            .gap(6)
            .truncate()
            .child(div().flex_none().text_color(c.active ? C.text : "#c4c6ca").child(c.name)),
        );
    };

    return h_flex().relative()
      .on_mouse_move((event,cx)=>{
        if (!this.drag) return;
        this.drag.pointer=event.local_position;
        this.drag.bounds=event.bounds;
        this.drag.lifted ||= Math.hypot(event.position.x-this.drag.start.x,event.position.y-this.drag.start.y)>4;
        this.drag.valid=event.position.x>=this.drag.origin;
        if(this.drag.lifted && this.drag.valid) this.drag.index=insertionSlot(this.drag.sizes,this.drag.gap,3,this.drag.index,event.position.x-this.drag.origin);
        cx.notify();
      })
      .on_hover((hovered,cx)=>{if (!hovered && this.drag) {this.drag=null;cx.notify();}})
      .on_mouse_up("left",(_event,cx)=>{
        if(this.drag?.lifted){if(this.drag.valid!==false)this.dropTabs(this.drag);this.suppressClick=true;}
        this.drag=null;cx.notify();
      })
      .on_mouse_down_out(()=>{this.drag=null;})
      .on_scroll_wheel((_event,cx)=>{if(this.drag){this.drag=null;this.suppressClick=true;cx.notify();}})
      .size_full()
      .gap(8)
      .items_center()
      // macOS: the window buttons sit here (the layout's traffic_lights).
      .when(w.platform === "macos" && w.titlebar === "none" && !w.fullscreen, (el) => el.pl(72))
      .child(
        own(h_flex())
          .id("tm-space")
          .flex_none()
          .h(30)
          .pl(10)
          .pr(12)
          .gap(8)
          .items_center()
          .rounded_full()
          .bg(C.chip)
          .cursor_pointer()
          .text_size(13)
          .text_color(C.dim)
          .hover((s) => s.text_color(C.text))
          .on_click(() => openOverlay({ mod: "picker", kind: "popup", at: "top", offset: 40, width: 640, height: 0.8 }))
          .child(svg("mods/terminals-bar/stack.svg").size(15))
          .child(div().max_w(160).truncate().text_color(C.text).child(space.name)),
      )
      .child(
        h_flex()
          .id("compact-tabs")
          .overflow_x_scrollbar()
          .on_scroll_wheel((_event,cx)=>{if(this.drag){this.drag=null;this.suppressClick=true;cx.notify();}})
          .flex_shrink(1)
          .min_w(0)
          .h(36)
          .p(3)
          .gap(3)
          .rounded(16)
          .bg(C.tray)
          .children((this.drag?.lifted && this.drag.valid!==false ? (()=>{
            const remaining=space.tabs.filter(c=>!this.drag.ids.includes(c.id));
            remaining.splice(this.drag.index,0,{gap:true,width:this.drag.gap});
            return remaining;
          })() : space.tabs).map(tab)),
      )
      .when(this.selected.length > 1, el => el.child(
        h_flex().flex_none().gap(3).items_center()
          .child(div().text_size(11).text_color(C.dim).child(this.busy ? "Closing tabs" : `${this.selected.length} selected`))
          .child(own(div()).id("group-left").px(6).py(4).cursor_pointer().on_click(()=>this.moveSelected(-1))
            .child(svg("mods/workspace-chrome/chevron-left.svg").size(16).text_color(C.text)))
          .child(own(div()).id("group-right").px(6).py(4).cursor_pointer().on_click(()=>this.moveSelected(1))
            .child(svg("mods/workspace-chrome/chevron-right.svg").size(16).text_color(C.text)))
      ))
      .child(div().flex_1())
      .child(iconButton("tm-keys", "command", () => run("app.palette")))
      .child(iconButton("tm-new", "plus", () => run("tab.new", { space: space.id })))
      .when(this.drag?.lifted && this.drag.pointer, el=>el.child(
        div().id("tab-drag-preview").absolute().left(Math.max(8,Math.min(this.drag.pointer.x+10,this.drag.bounds.width-168))).top(0)
          .transition("left",{duration:65,easing:"ease-out"}).w(160).h(34).px(10)
          .flex().items_center().rounded(10).border_1().border_color(this.drag.valid===false ? t.ansi1 : "#86b4cb")
          .bg(C.tab).shadow_lg().opacity(0.95).text_size(12).text_color(C.text)
          .child(div().truncate().child(this.drag.ids.length>1 ? `${this.drag.name} + ${this.drag.ids.length-1}` : this.drag.name))
      ))
      .when(Boolean(w.buttons), (el) =>
        el.child(
          h_flex()
            .flex_none()
            .pl(6)
            .pr(4)
            .gap(8)
            .child(windowButton("tm-min", "win-min", "window.minimize"))
            .child(windowButton("tm-max", w.maximized ? "win-restore" : "win-max", "window.maximize"))
            .child(windowButton("tm-close", "win-close", "window.close")),
        ),
      );
  }
}
