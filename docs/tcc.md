# TCC: auditing and purging grants

The grant lists themselves are snapshot steps in MANUAL-<host>.md.

`capture-snapshot tcc` reads **both** the system and current user's TCC
databases, read-only. It records every service with a nonzero authorization
value for clients still present, including Automation's individual target
apps. The system database alone misses user permissions such as Camera,
Photos, Contacts, Calendar, Microphone and Files and Folders.

Each sorted row is `service|client|auth=N`, with `|target=<identifier>` when
TCC records a target. `auth=2` is the usual allow value; other nonzero
values are preserved verbatim, not interpreted as a grant. Denied rows
(`auth=0`) and clients no longer present are omitted. These are normalized
reference lists, not copies of the databases: signing requirements, timestamps
and process metadata are not captured. User home paths become `~/`, and Nix
store hashes and Homebrew Cellar versions become `*` for stable comparison.
Spotlight and LaunchServices resolve non-Apple bundle IDs, including installed
helper apps that Spotlight does not index. Stale LaunchServices paths are omitted.

Refresh either host from either Mac:

```Shell
just snapshot tcc macbook-air
just snapshot tcc mac-mini
just manual
```

The recipe queries the selected host over SSH and preserves its previous
snapshot if capture fails. Both stores require Full Disk Access in the
capturing shell's context; a read failure exits 3 rather than reporting a
partial snapshot as success.

On a replacement computer, install the declared apps first, then use the
host's `MANUAL-<host>.md` and `snapshots/<host>/tcc.txt` as a reference in
System Settings → Privacy & Security. Trigger each app's native permission
prompt as needed, including each listed Automation target. Nix records and
checks these permissions; it does not restore the databases or grant consent.
Apple-internal cloud services and nonstandard auth values are observations,
not instructions to manufacture grants. Run `manual-check` after setup and
compare any remaining differences with `capture-snapshot tcc --diff <snapshot>`.

Path-keyed clients (brew's versioned node/claude-code paths) re-key on every
version bump and just shed a dead row. Harmless - leave them unless removal
is explicitly requested.

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
