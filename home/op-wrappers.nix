{
  config,
  pkgs,
  nix-openclaw-tools,
  ...
}:

# The op-authed CLI wrapper family — one paradigm, one file. PATH-level
# shadows (not aliases/functions, so scripts, launchd, justfiles, and agent
# shells all get auth; the real binary must not be installed anywhere else
# or PATH order decides) that inject credentials from the AI Agent vault via
# `op read` at call time — nothing credential-shaped ever touches disk.
#
# Shared shape: caller-set env vars win → agent-detect.sh maps agent CLIs to
# AGENT_SHELL → agent-op-env.sh arms the SA token in agent contexts and
# defines op_has_auth → op read (desktop-app auth, Touch ID, in Alex's own
# terminals) → exec the real binary. Both seams are interpolated
# (builtins.readFile) because wrapper callers may skip zshrc entirely.
# opConnect.cliPackage selects local Connect for supported agent-vault reads
# when enabled; document operations and writes keep direct authentication.
# EVERY op call in here sits behind op_has_auth: with no auth source at all
# (Alex's own ssh shells on the mini) op prompts on /dev/tty and hangs
# headless callers, and 2>/dev/null does not suppress a prompt.
#
# Exported via homeModules; consumers must pass `nix-openclaw-tools` through
# extraSpecialArgs (for gog).
let
  # gogcli from the openclaw flake — tracks upstream releases; nixpkgs' copy
  # lags months behind at gog's weekly cadence.
  gogcliPkg = nix-openclaw-tools.packages.${pkgs.stdenv.hostPlatform.system}.gogcli;
  posthogCli = pkgs.callPackage ../pkgs/posthog-cli.nix { };
  # wacli (WhatsApp linked-device CLI) from its GitHub release — not in
  # nixpkgs or nix-openclaw-tools. Installed under libexec on purpose: the
  # `wacli` on PATH must be the wrapper below, never the raw binary.
  wacliBin = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "wacli";
    version = "0.18.0";
    src = pkgs.fetchurl {
      url = "https://github.com/openclaw/wacli/releases/download/v${version}/wacli_${version}_universal_darwin_all.tar.gz";
      hash = "sha256-oKrqBuApgmsrYZAwc2sFXZMETovnjWJUl5jKGkU5QR0=";
    };
    sourceRoot = ".";
    dontStrip = true;
    installPhase = ''
      mkdir -p $out/libexec/wacli
      install -m755 wacli $out/libexec/wacli/wacli
    '';
    meta.platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
    ];
  };
in
{
  imports = [ ./op-connect.nix ];
  xdg.dataFile."posthog/skills".source = "${posthogCli.skills}/skills";
  home.packages = [
    # Agent-wide PostHog access, using the existing broad personal API key.
    (pkgs.writeShellApplication {
      name = "posthog-cli";
      runtimeInputs = [ config.opConnect.cliPackage ];
      text = ''
        ${builtins.readFile ./agent-detect.sh}
        ${builtins.readFile ./agent-op-env.sh}
        ${builtins.readFile ./posthog-auth.sh}
        exec ${posthogCli}/bin/posthog-cli "$@"
      '';
    })

    # gh, ALWAYS authed via 1Password (PAT item in the AI Agent vault) — the
    # keyring is not used.
    (pkgs.writeShellApplication {
      name = "gh";
      runtimeInputs = [ config.opConnect.cliPackage ];
      text = ''
        if [ -z "''${GH_TOKEN:-}''${GITHUB_TOKEN:-}" ]; then
          ${builtins.readFile ./agent-detect.sh}
          ${builtins.readFile ./agent-op-env.sh}
          if op_has_auth; then
            GH_TOKEN="$(op read 'op://4eeyrkqibibn7k4j6rz2fbzvxm/spmkea5afgjzcekuahclmwowxq/token')"
            if [ -n "$GH_TOKEN" ]; then export GH_TOKEN; fi
          fi
        fi
        exec ${pkgs.gh}/bin/gh "$@"
      '';
    })

    # modal, ALWAYS authed via 1Password (AI Agent vault) — ~/.modal.toml is
    # never written. Inside a uv project the project's pinned modal wins; the
    # sentinel stops `uv run modal` re-entering this wrapper when the project
    # has no modal dependency.
    (pkgs.writeShellApplication {
      name = "modal";
      runtimeInputs = [
        config.opConnect.cliPackage
        pkgs.uv
      ];
      text = ''
        if [ -z "''${MODAL_TOKEN_ID:-}" ]; then
          ${builtins.readFile ./agent-detect.sh}
          ${builtins.readFile ./agent-op-env.sh}
          if op_has_auth; then
            MODAL_TOKEN_ID="$(op read 'op://4eeyrkqibibn7k4j6rz2fbzvxm/2sfxybjpv3c3ohzxhf5qeken4a/token_id')"
            MODAL_TOKEN_SECRET="$(op read 'op://4eeyrkqibibn7k4j6rz2fbzvxm/2sfxybjpv3c3ohzxhf5qeken4a/token_secret')"
            if [ -n "$MODAL_TOKEN_ID" ] && [ -n "$MODAL_TOKEN_SECRET" ]; then
              export MODAL_TOKEN_ID MODAL_TOKEN_SECRET
            fi
          fi
        fi
        in_uv_project=0
        d=$PWD
        while [ "$d" != "/" ]; do
          if [ -f "$d/pyproject.toml" ]; then in_uv_project=1; break; fi
          d=$(dirname "$d")
        done
        if [ "$in_uv_project" = 0 ] || [ -n "''${_MODAL_WRAPPED:-}" ]; then
          exec uvx modal "$@"
        fi
        export _MODAL_WRAPPED=1
        exec uv run modal "$@"
      '';
    })

    # gog (Google CLI), wrapped with 1P-ONLY credential storage: gog itself
    # never sees a refresh token. The wrapper owns the OAuth refresh: the
    # "AI Agent Gog Token Export" item holds the refresh token (credential
    # field, `gog auth tokens export` JSON) plus a cached
    # access_token/expires_at pair the wrapper writes back after each
    # refresh; "AI Agent Gog OAuth Client" holds the client JSON. Fast path
    # (access token still valid) = ONE op call, no Google round-trip; slow
    # path (~hourly) = curl refresh + 1P writeback. gog runs in
    # --access-token mode throughout (bypasses stored tokens). The macOS
    # keychain backend stays banned: structurally broken for nix binaries
    # (adhoc-signed, store path changes each rebuild → ACL prompt flood).
    # Caller-set GOG_ACCESS_TOKEN or GOG_HOME bypasses everything (the
    # consent bootstrap uses GOG_HOME; see the gog skill).
    (pkgs.writeShellApplication {
      name = "gog";
      runtimeInputs = [
        config.opConnect.cliPackage
        pkgs.jq
        pkgs.curl
      ];
      text = ''
        if [ -n "''${GOG_ACCESS_TOKEN:-}''${GOG_HOME:-}" ]; then
          exec ${gogcliPkg}/bin/gog "$@"
        fi
        ${builtins.readFile ./agent-detect.sh}
        ${builtins.readFile ./agent-op-env.sh}
        item=""
        if op_has_auth; then
          item="$(op item get jjc6xu22cew46e6zpyfdsdjv3e --vault 4eeyrkqibibn7k4j6rz2fbzvxm --format json)"
        fi
        if [ -n "$item" ]; then
          at="$(jq -r '[.fields[] | select(.label == "access_token")][0].value // empty' <<<"$item")"
          exp="$(jq -r '[.fields[] | select(.label == "expires_at")][0].value // empty' <<<"$item")"
          case "$exp" in ("" | *[!0-9]*) exp=0 ;; esac
          now="$(date +%s)"
          if [ -n "$at" ] && [ "$now" -lt "$((exp - 60))" ]; then
            export GOG_ACCESS_TOKEN="$at"
            exec ${gogcliPkg}/bin/gog "$@"
          fi
          # Access token missing/expired: refresh it ourselves and cache it
          # back into the item. Secrets travel via stdin, never argv.
          rt="$(jq -r '[.fields[] | select(.id == "credential")][0].value // empty' <<<"$item" | jq -r '.refresh_token // empty')"
          client="$(op read 'op://4eeyrkqibibn7k4j6rz2fbzvxm/4x66lrvreiljbmepa6esgkyu2e/credential')"
          cid="$(jq -r '.installed.client_id // .web.client_id // empty' <<<"$client" 2>/dev/null || true)"
          csec="$(jq -r '.installed.client_secret // .web.client_secret // empty' <<<"$client" 2>/dev/null || true)"
          if [ -n "$rt" ] && [ -n "$cid" ]; then
            resp="$(printf 'grant_type=refresh_token&client_id=%s&client_secret=%s&refresh_token=%s' "$cid" "$csec" "$rt" \
              | curl -s --max-time 30 --data @- https://oauth2.googleapis.com/token || true)"
            at="$(jq -r '.access_token // empty' <<<"$resp" 2>/dev/null || true)"
            expin="$(jq -r '.expires_in // 3600' <<<"$resp" 2>/dev/null || echo 3600)"
            if [ -n "$at" ]; then
              op item edit jjc6xu22cew46e6zpyfdsdjv3e --vault 4eeyrkqibibn7k4j6rz2fbzvxm \
                --tags "$(jq -r '(.tags // []) | join(",")' <<<"$item")" "access_token[concealed]=$at" "expires_at[text]=$((now + expin))" >/dev/null 2>&1 || true
              export GOG_ACCESS_TOKEN="$at"
            else
              # invalid_grant = refresh token revoked (password change / 6mo
              # idle / consent withdrawn) → human re-consent is the only fix.
              err="$(jq -r '.error // empty' <<<"$resp" 2>/dev/null || true)"
              echo "gog wrapper: token refresh failed (''${err:-no response from Google}) — refresh token likely revoked. Fix: Alex runs \`gog-auth-bootstrap\` in his own terminal (alias; script in the gog skill)." >&2
            fi
          fi
        fi
        exec ${gogcliPkg}/bin/gog "$@"
      '';
    })

    # wacli (WhatsApp CLI, tier 2 of the whatsapp skill) with the linked-device
    # SESSION in 1Password, so one pairing serves every machine. A WhatsApp
    # linked device is Signal ratchet state that advances on every message —
    # it must have exactly ONE live copy, so the wrapper round-trips it:
    # fetch session.db from the "AI Agent WhatsApp Linked Device Session"
    # document → run wacli against a local store → write session.db back iff
    # it changed. Only session.db travels; wacli.db (its message mirror) stays
    # per machine. A failed write-back leaves an .unsynced marker and the
    # next run pushes before pulling, so a newer local session is never
    # clobbered by the stale 1P copy. NEVER run wacli on two machines at the
    # same time — nothing here serializes writers (ponytail: discipline, not
    # a lock; add a 1P lock field if it ever bites). Caller-set
    # WACLI_STORE_DIR bypasses the round-trip (local/manual store).
    (pkgs.writeShellApplication {
      name = "wacli";
      runtimeInputs = [
        config.opConnect.cliPackage
        pkgs.sqlite
        pkgs.coreutils
      ];
      text = ''
        if [ -n "''${WACLI_STORE_DIR:-}" ]; then
          exec ${wacliBin}/libexec/wacli/wacli "$@"
        fi
        ${builtins.readFile ./agent-detect.sh}
        ${builtins.readFile ./agent-op-env.sh}
        if ! op_has_auth; then
          echo "wacli wrapper: no 1Password auth in this shell - the linked-device session lives in 1Password, refusing to run without it" >&2
          exit 1
        fi
        item=rnq2u2njglpcgtgbaw3ijdcuau   # AI Agent WhatsApp Linked Device Session (document)
        vault=4eeyrkqibibn7k4j6rz2fbzvxm  # AI Agent
        store="''${XDG_STATE_HOME:-$HOME/.local/state}/wacli"
        mkdir -p "$store"
        chmod 700 "$store"
        if [ -f "$store/session.db.unsynced" ]; then
          if op document edit "$item" "$store/session.db" --vault "$vault" >/dev/null; then
            rm -f "$store/session.db.unsynced"
          else
            echo "wacli wrapper: a previous run changed the session but could not write it back to 1Password, and this retry failed too - not running (op rate-limited or unauthenticated?)" >&2
            exit 1
          fi
        fi
        tmp="$(mktemp "$store/.session.XXXXXX")"
        if ! op document get "$item" --vault "$vault" --out-file "$tmp" --force >/dev/null; then
          rm -f "$tmp"
          echo "wacli wrapper: could not fetch the linked-device session from 1Password - refusing to run against a possibly stale local copy" >&2
          exit 1
        fi
        rm -f "$store/session.db-wal" "$store/session.db-shm"
        if [ -s "$tmp" ]; then
          mv "$tmp" "$store/session.db"
        else
          rm -f "$tmp" "$store/session.db"   # empty document = not paired yet
        fi
        before="$( { [ -f "$store/session.db" ] && sha256sum "$store/session.db"; } | cut -d' ' -f1 || true)"
        set +e
        WACLI_STORE_DIR="$store" ${wacliBin}/libexec/wacli/wacli "$@"
        rc=$?
        set -e
        if [ -f "$store/session.db" ]; then
          if [ -s "$store/session.db-wal" ]; then
            sqlite3 "$store/session.db" 'PRAGMA wal_checkpoint(TRUNCATE);' >/dev/null 2>&1 || true
          fi
          after="$(sha256sum "$store/session.db" | cut -d' ' -f1)"
          if [ "$after" != "$before" ]; then
            if ! op document edit "$item" "$store/session.db" --vault "$vault" >/dev/null; then
              touch "$store/session.db.unsynced"
              echo "wacli wrapper: WARNING - the session changed but could not be written back to 1Password; it will be pushed on the next run from THIS machine. Do not run wacli elsewhere until then." >&2
            fi
          fi
        fi
        exit "$rc"
      '';
    })

    # wrangler, ALWAYS authed via 1Password (AI Agent Cloudflare API Key) —
    # CLOUDFLARE_API_TOKEN takes precedence over wrangler's cached OAuth
    # config, so ~/.wrangler/config/default.toml is never written or read.
    # The token is account-scoped, so wrangler infers the account ID itself.
    (pkgs.writeShellApplication {
      name = "wrangler";
      runtimeInputs = [ config.opConnect.cliPackage ];
      text = ''
        if [ -z "''${CLOUDFLARE_API_TOKEN:-}" ]; then
          ${builtins.readFile ./agent-detect.sh}
          ${builtins.readFile ./agent-op-env.sh}
          if op_has_auth; then
            CLOUDFLARE_API_TOKEN="$(op read 'op://4eeyrkqibibn7k4j6rz2fbzvxm/mxxpo6neiz3grdyrjj7rv7nume/credential')"
            if [ -n "$CLOUDFLARE_API_TOKEN" ]; then export CLOUDFLARE_API_TOKEN; fi
          fi
        fi
        exec ${pkgs.wrangler}/bin/wrangler "$@"
      '';
    })

    # gcloud, ALWAYS authed via 1Password (GCP SA key item in the AI Agent
    # vault). Replaces the brew gcloud-cli cask and the interactive-only op
    # plugin alias. The key JSON transits a 0600 mktemp file removed on exit
    # (same mechanism `op plugin run` uses internally).
    (pkgs.writeShellApplication {
      name = "gcloud";
      runtimeInputs = [ config.opConnect.cliPackage ];
      text = ''
        if [ -n "''${CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE:-}''${GOOGLE_APPLICATION_CREDENTIALS:-}" ]; then
          exec ${pkgs.google-cloud-sdk}/bin/gcloud "$@"
        fi
        ${builtins.readFile ./agent-detect.sh}
        ${builtins.readFile ./agent-op-env.sh}
        keyfile="$(mktemp "''${TMPDIR:-/tmp}/gcloud-key-XXXXXX")"
        trap 'rm -f "$keyfile"' EXIT
        if op_has_auth; then
          op read 'op://4eeyrkqibibn7k4j6rz2fbzvxm/iqywn6he6twhyonw3fhnqmot5i/credential' > "$keyfile"
          [ -s "$keyfile" ] || exit 1
          export CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE="$keyfile"
        fi
        ${pkgs.google-cloud-sdk}/bin/gcloud "$@"
      '';
    })

    # ntn (Notion CLI), ALWAYS authed via 1Password (the AI Agent Notion
    # internal-integration secret). NOTION_API_TOKEN overrides ntn's own
    # workspace login, which is deliberately never established — without this
    # wrapper every caller had to paste the op:// ref out of a skill.
    # The binary is a Homebrew cask (not in nixpkgs), so this execs it by
    # absolute path; the nix profile sorts ahead of Homebrew on PATH, so
    # plain `ntn` resolves to this wrapper.
    (pkgs.writeShellApplication {
      name = "ntn";
      runtimeInputs = [ config.opConnect.cliPackage ];
      text = ''
        if [ -z "''${NOTION_API_TOKEN:-}" ]; then
          ${builtins.readFile ./agent-detect.sh}
          ${builtins.readFile ./agent-op-env.sh}
          if op_has_auth; then
            NOTION_API_TOKEN="$(op read 'op://4eeyrkqibibn7k4j6rz2fbzvxm/nhsh73sfidj4cdowvbaayaq7tq/credential')"
            if [ -n "$NOTION_API_TOKEN" ]; then export NOTION_API_TOKEN; fi
          fi
        fi
        exec "''${HOMEBREW_PREFIX:-/opt/homebrew}/bin/ntn" "$@"
      '';
    })
  ];
}
