# TCC: auditing and purging grants

The grant lists themselves are snapshot steps in MANUAL-<host>.md.

Snapshot verified against the system TCC db 2026-10-10. Audit anytime with:

```Shell
sudo sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" \
  "SELECT service, client FROM access WHERE auth_value > 0 AND service IN
   ('kTCCServiceAccessibility','kTCCServiceListenEvent',
    'kTCCServiceScreenCapture','kTCCServiceSystemPolicyAllFiles',
    'kTCCServiceCalendar','kTCCServiceAddressBook','kTCCServiceMicrophone')
   ORDER BY service, client;"
```

Path-keyed clients (brew's versioned node/claude-code paths) re-key on every
version bump and just shed a dead row. Harmless — purge dead rows whenever
auditing.

Purging dead rows: `tccutil reset` does NOT work for uninstalled software
(it errors "No such bundle identifier" once the app leaves LaunchServices)
and can't address path-keyed clients at all. The user db takes a direct
DELETE from a Full Disk Access shell:

```Shell
sqlite3 "$HOME/Library/Application Support/com.apple.TCC/TCC.db" \
  "DELETE FROM access WHERE client IN ('<bundle-id-or-path>', ...); SELECT changes();"
```

The system db (where Accessibility, Screen Recording and Full Disk Access
live) refuses it with SIP on: `sudo sqlite3` from a plain OpenSSH session
that holds Full Disk Access still fails with "attempt to write a readonly
database (8)" on macOS 26. Dead system-db rows therefore stay.
They grant nothing, and `capture-snapshot tcc` lists only rows whose app or
client path still exists, so they never show as drift.
