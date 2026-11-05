# Herdr Multiple Tabs Implementation Plan

**Goal:** Shift-click a range of tabs, move the selection left/right within its space, and close the selection with Cmd+W.

**Architecture:** Keep selection in the compact tab bar, scoped to its space. Route Cmd+W to that live mod only in the custom layout; the mod invokes the native helper with explicit tab IDs. Preflight the group before any close, then use the existing durable archive path per tab. Other layouts retain normal closing. Undo restores tabs individually.

**Tech Stack:** Existing Herdr GPUI JavaScript mod and Python native helper.

- [x] Test range selection, stale IDs, boundary moves and relative order before implementing pure helpers in the existing mod.
- [x] Add selected styling and minimal left/right controls. Clear selection on plain click or space change.
- [x] Test and implement explicit group close validation and preflight, preserving the archive path and existing single-tab close.
- [ ] Wire live mod commands and error reporting. Verify native mods, rebuild laptop, run disposable shell selection/movement/close/restore fixtures, then clean up.
- [ ] Commit, push, close associated tasks and deliver verification.

User-approved additions: drag single tabs and selected groups in either bar within a space; two-word agent titles; native agent icons and traffic-light status dots in both bars; omit unnamed home-space headings; extend Hammerspoon copy confirmation to native Herdr.

Review corrections: reset drag click suppression per press, clear old selection when dragging an unselected tab, aggregate top-tab status across panes, and run group close in a core-owned worker so it can exceed the UI command timeout. Native eased floating previews follow the drag in both bars.
