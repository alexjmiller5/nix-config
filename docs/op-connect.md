# Local 1Password Connect

`homeModules.op-connect` runs the official API and sync containers on Docker
Desktop. The laptop enables it; both machines use the shared operator auth router.
The API listens at `http://127.0.0.1:8080` by default. Containers restart when
Docker restarts. The login service opens Docker and runs Compose at login.

The installed `op` wrapper routes agent `op read op://<configured-vault-id>/...`
and `op item get ... --vault <configured-vault-id> --format json` through
Connect. CLI wrappers such as `gh`, `ntn`, `modal`, `spotify_player` and `posthog-cli` consume
that package automatically. The command and secret references stay the same.
Writes, Documents, `op run`, `op inject`, human shells, explicit project SAs,
and other vaults use direct authentication. Explicit other-vault references
use user auth. `op-auth desktop` selects user auth for the current agent
session; `op-personal <op arguments>` selects it for one operation.
See [operator authentication](op-auth.md).

## Credentials and startup

1. The credentials Document and dedicated read-only Connect token live in
   the configured 1Password vault, referenced by IDs in the host module.
2. At login, the service uses the independently enrolled agent SA from the
   existing `~/.local/state/op/agent-sa-token` file to restore a missing
   `1password-credentials.json` into `$XDG_STATE_HOME/1password-connect`
   (default `~/.local/state/1password-connect`). Directory permissions are
   `0700`; the file is `0600` and mounted read-only into both containers.
3. It reads the Connect token once and retains it in memory. A `0600` Unix
   socket in that private directory gives each op process its token. The
   token is never saved to a file, put in process arguments, exported by
   shell initialization, or passed to Docker.
4. Docker starts the two containers. Connect encrypts its cached vault data
   in the shared named volume. The credentials bundle's sensitive payload
   is itself encrypted; the bearer token supplies its decryption material.

The service reads one cloud item per start, plus one Document when restoring
the bundle. Routine eligible reads go to localhost. Token lifetime is the
login service's lifetime, independent of how many agent sessions or tool
shells open. Logging out drops the in-memory copy. Connect's encrypted data
volume and the encrypted credentials bundle persist.

## Operate and recover

- `op-connect-start`: restart the declared login service, reload the token
  from 1Password, and start the containers. Use after token rotation or a
  startup failure. This performs a cloud read.
- `docker compose -f ~/.config/1password-connect/compose.json ps`: container
  status. Use the same file with `logs --tail 30` for container diagnostics.
- `~/Library/Logs/op-connect.log`: startup diagnostics, without secret values.
- If Connect is down, eligible reads fail with a recovery message. They do
  not silently fall back to the metered SA. Run `op-auth desktop`
  explicitly when direct user auth is needed.
- Startup does not automatically retry a failed cloud-auth request. Resolve
  the auth issue and restart the service. Existing SA quota exhaustion uses
  the normal desktop-auth protocol; restarting cannot reset that quota.

## Reproduce provisioning

An enrolled laptop keeps its existing agent credential file, encrypted
Connect bundle and Docker volume. A replacement laptop first needs
[independent operator enrollment](../MANUAL-macbook-air.md#agent-operator-credentials-enrollment-and-rotation)
from the authoritative AI Agent credential record using native user auth.
Nix bootstrap and machine service accounts do not populate that file.
Once enrolled, the existing item IDs let Connect restore a missing bundle
and load its token at service startup; no new Connect server is needed.
Startup still requires working agent SA access, including available quota.

For an independent new deployment, run the installed bootstrap with desktop
authentication (or `python3 scripts/op-connect-bootstrap.py` before the first
Nix activation):

```sh
op-connect-bootstrap --vault <vault-id> --server <server-name> \
  --owner <vault-owner> --state-directory <private-state-directory>
```

It creates the server, backs up the generated bundle as a tagged Document,
creates a read-only token, saves it as a concealed field, and prints only
stable IDs. Re-running reuses the existing server and vault items. Configure
`opConnect.enable`, `vaultId`, `credentialsItemId`, and `tokenOpRef` using that
output, then rebuild. Each separate deployment needs its own credentials;
the bootstrap's item titles must be unique within its owning vault.

Docker Desktop's initial agreement and 1Password desktop sign-in can require
user interaction. These are the GUI prerequisites; routine startup is Nix
managed. Other options configure paths, port, image version and Compose
project name without embedding secret values in Nix.

Official references: [deployment](https://www.1password.dev/connect/get-started),
[supported CLI commands](https://www.1password.dev/connect/cli), and
[credential encryption](https://support.1password.com/business-security-practices/#1password-integrations).
