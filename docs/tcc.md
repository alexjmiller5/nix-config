# TCC: auditing and purging grants

The grant lists themselves are snapshot steps in MANUAL-<host>.md.

Snapshot verified against the system TCC db 2026-08-13. Audit anytime with:

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
and can't address path-keyed clients at all. Delete rows directly instead —
same statement against both dbs (user db needs an FDA'd shell, system db
needs sudo), then bounce tccd:

```Shell
sqlite3 "$HOME/Library/Application Support/com.apple.TCC/TCC.db" \
  "DELETE FROM access WHERE client IN ('<bundle-id-or-path>', ...); SELECT changes();"
sudo sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" \
  "DELETE FROM access WHERE client IN ('<bundle-id-or-path>', ...); SELECT changes();"
sudo killall tccd
```
