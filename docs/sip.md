# SIP status: DISABLED - keep it that way for now

SIP is currently disabled on this machine. **Deliberately kept disabled** since
2026-08-26: macOS ≥26.3 locks the ScreenTimeAgent store (the
DeviceActivity/Cloud segments that carry cross-device per-app AND per-site
Screen Time, incl. iPhone web domains) behind kernel sandbox/TCC enforcement
that even Full Disk Access can't cross — SIP-off plausibly bypasses it.
This 26.1 machine is the only capture point for that data
(screentime-backup agent). Before/after any macOS update past 26.2, verify
the store is still readable:
`ls "$(getconf DARWIN_USER_DIR)com.apple.ScreenTimeAgent/Store/Library/com.apple.DeviceActivity/Cloud"`
If it EPERMs with SIP off, per-site capture is over — reassess then.
(Disabling SIP again after an update re-enables it: the yabai wiki has the
best step-by-step guide —
https://github.com/koekeishiya/yabai/wiki/Disabling-System-Integrity-Protection
— including the Apple-silicon Recovery flow and which csrutil flags to use.
Restoring SIP: `csrutil enable` in Recovery; boot-arg cleanup:
`sudo nvram -d boot-args`.)
