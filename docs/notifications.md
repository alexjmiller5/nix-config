# Notifications: what's declared vs manual

Declared, `home/macos/notification-prefs.nix` + the block in
`home/macbook-air.nix`: per-app "Allow notifications" (`enable`), plus alert
style / venues / badge / sound / summarize (`flags`), Show previews
(`content_visibility`) and Notification grouping (`grouping`). Re-capture with
`scripts/capture-notification-prefs` after changing anything in the UI —
uninstalled apps drop out on every capture, so the list stays honest.

The live store is usernoted's group container, NOT
`~/Library/Preferences/com.apple.ncprefs.plist`. That path looks like the
right one and is what every guide online names, but on this machine it is a
stale copy: it still listed apps uninstalled months ago, was missing every
recently-installed one, and writes to it changed nothing in the UI.

`enable` maps onto two `flags` bits rather than a field of its own: an app is
allowed iff bit 23 is clear OR bit 25 is set (bit 23 records that a choice was
made, bit 25 carries allow/deny). Verified 2026-09-01 end to end by flipping
one app in nix and watching System Settings switch it from Off to on.

**Quit System Settings to SEE a switch's changes.** It caches the app list at
launch and never notices an external write, so switching with it open leaves
the Notifications pane showing the old values — quit and reopen it (navigating
away and back is not enough). This is display-only: the write itself lands and
survives, and System Settings does not clobber it on quit, so there is no need
to quit *before* switching. Same for checking state from the shell, which
always reads live: `scripts/capture-notification-prefs | grep -A1 '"<bundle>"'`.

Manual: the OS's own notification sources (Wi-Fi, Bluetooth, Software Update,
tccd — the `_SYSTEM_CENTER_:` entries and the bundles under
`/System/Library/UserNotifications/`) are deliberately left undeclared; their
values churn with OS updates.
