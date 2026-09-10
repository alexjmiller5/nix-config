# Local 1Password Connect

`homeModules.op-connect` runs the official API and sync containers on Docker
Desktop. The laptop enables it; the mini keeps its existing authentication.
The API listens at `http://127.0.0.1:8080` by default. Containers restart when
Docker restarts. The login service opens Docker and runs Compose at login.

The installed `op` wrapper routes agent `op read op://<configured-vault-id>/...`
and `op item get ... --vault <configured-vault-id> --format json` through
Connect. CLI wrappers such as `gh`, `ntn`, `modal`, `spotify_player` and `posthog-cli` consume
that package automatically. The command and secret references stay the same.
Writes, Documents, `op run`, `op inject`, human shells, explicit project SAs,
and other vaults use direct authentication. `AGENT_OP_AUTH=desktop` clears
both SA and Connect credentials for desktop authentication.

## Credentials and startup

1. The credentials Document and dedicated read-only Connect token live in
   the configured 1Password vault, referenced by IDs in the host module.
2. At login, the service uses the existing agent SA to restore a missing
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
  not silently fall back to the metered SA. Select `AGENT_OP_AUTH=desktop`
  explicitly when direct user auth is needed.
- Startup does not automatically retry a failed cloud-auth request. Resolve
  the auth issue and restart the service. Existing SA quota exhaustion uses
  the normal desktop-auth protocol; restarting cannot reset that quota.

## Reproduce provisioning

Restoring the existing laptop configuration needs no new Connect server or
manual secret copying: existing item IDs restore the working bundle and
load the token through the normal machine/agent SA bootstrap.

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
