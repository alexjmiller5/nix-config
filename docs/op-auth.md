# Operator authentication

Use ordinary `op`, `gh`, `git`, `ntn` and the other installed CLI wrappers.
`homeModules.op-auth` supplies the shared `op` entry point on both Macs.
Agent contexts use the independently enrolled operator SA automatically.
The laptop uses local Connect for supported reads; the mini uses direct SA
access. Human shells keep their native user authentication.

```sh
op-auth status       # auto or desktop for this session
op-auth desktop      # select desktop once for the current agent session
op-personal read 'op://<vault-id>/<item-id>/<field>' # user auth for one call
```

On a confirmed direct-SA quota error the router remembers desktop mode for
the session and retries a read once with user auth. Later tool calls and Git
signing read the same preference. No SA recovery polling occurs. Generic
network, GitHub or item-not-found errors do not change authentication.
Writes are never repeated automatically; a confirmed quota error selects
desktop mode for subsequent calls and reports that the write was not retried.
`op run` executes once with native streams and signals; its child errors
cannot be mistaken for a 1Password quota error.

Explicit project SA tokens, caller-provided Connect credentials and service
credentials such as `GH_TOKEN` keep their existing scope and precedence.
An explicit different vault ID in `op read` or `--vault` selects user auth
only for that operation. The router does not inspect template files or
interpret child command arguments: use `op-personal run --env-file=... -- ...`
for a project template, or select session desktop mode before a provisioning
script. An explicit `AGENT_OP_AUTH=desktop` override remains supported.

Desktop auth uses the installed 1Password app on the laptop. The mini uses
its existing supported `op-unlock` user-session window. If user auth is
unavailable, the command fails; it does not return to the exhausted SA.
Connect outages remain explicit errors; `op-auth desktop` selects an
alternative without consuming more SA quota.

Session markers contain only `desktop` and live in a private directory at
`$XDG_STATE_HOME/op/auth-sessions` (default `~/.local/state/op/auth-sessions`).
Codex uses its native thread/session ID. Claude's native SessionStart hook
writes its session ID into the environment file supplied by Claude; that
file also sources the shared initializer before each tool call. Start Claude
from a fresh shell after changing hook or shell configuration. Resume retains
the session preference; a new session starts in auto mode. No session marker
is shared between independent agent sessions.

Replacement machines enroll operator credentials and native app sessions
using the host manuals. Nix does not create or refresh credentials. The
module exposes the operator vault ID and credential-file path, with an
optional Connect configuration supplied by `homeModules.op-connect`.

Verification: `python3 tests/op-auth.py`, `bash tests/agent-detect.sh`,
`bash tests/op-auth-guard.sh`, and `python3 tests/op-connect.py`. The native
Claude hook is checked by agent-config's `tests/agent-session-env.py`.
