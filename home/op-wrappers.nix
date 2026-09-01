{ pkgs, nix-openclaw-tools, ... }:

# The op-authed CLI wrapper family — one paradigm, one file. PATH-level
# shadows (not aliases/functions, so scripts, launchd, justfiles, and agent
# shells all get auth; the real binary must not be installed anywhere else
# or PATH order decides) that inject credentials from the AI Agent vault via
# `op read` at call time.
#
# Shared shape: caller-set env vars win → agent-detect.sh maps agent CLIs to
# AGENT_SHELL → agent-op-env.sh arms the SA token in agent contexts →
# op-cache.sh's op_cached (TTL-cached op read — the account-wide SA budget is
# only 1000 requests/24h, so per-call reads are not affordable in the
# wrappers agents call in loops) → exec the real binary. All three seams are
# interpolated (builtins.readFile) because wrapper callers may skip zshrc
# entirely.
#
# gcloud and gog still read per call: gcloud is laptop-only and rare, and
# gog already caches its access token in 1P by design. Cache them the same
# way if either ever shows up as a budget burner.
#
# Exported via homeModules; consumers must pass `nix-openclaw-tools` through
# extraSpecialArgs (for gog).
let
  # gogcli from the openclaw flake — tracks upstream releases; nixpkgs' copy
  # lags months behind at gog's weekly cadence.
  gogcliPkg = nix-openclaw-tools.packages.${pkgs.stdenv.hostPlatform.system}.gogcli;
in
{
  home.packages = [
    # gh, ALWAYS authed via 1Password (PAT item in the AI Agent vault) — the
    # keyring is not used.
    (pkgs.writeShellApplication {
      name = "gh";
      runtimeInputs = [ pkgs._1password-cli ];
      text = ''
        if [ -z "''${GH_TOKEN:-}''${GITHUB_TOKEN:-}" ]; then
          ${builtins.readFile ./agent-detect.sh}
          ${builtins.readFile ./agent-op-env.sh}
          ${builtins.readFile ./op-cache.sh}
          # SA token → headless; otherwise desktop-app auth (Touch ID).
          # No auth source at all (Alex's own ssh shells on the mini): skip —
          # op read would prompt "add an account?" on /dev/tty and
          # hang/garble headless callers.
          # Cached: gh is the most-called wrapper by far (every push, every
          # gh api), and one op request per call exhausts the account-wide
          # 1000/24h budget in a single busy agent session.
          if [ -n "''${OP_SERVICE_ACCOUNT_TOKEN:-}" ] || [ -n "$(op account list 2>/dev/null)" ]; then
            GH_TOKEN="$(op_cached gh-token 'op://4eeyrkqibibn7k4j6rz2fbzvxm/spmkea5afgjzcekuahclmwowxq/token')"
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
        pkgs._1password-cli
        pkgs.uv
      ];
      text = ''
        if [ -z "''${MODAL_TOKEN_ID:-}" ]; then
          ${builtins.readFile ./agent-detect.sh}
          ${builtins.readFile ./agent-op-env.sh}
          ${builtins.readFile ./op-cache.sh}
          if [ -n "''${OP_SERVICE_ACCOUNT_TOKEN:-}" ] || [ -n "$(op account list 2>/dev/null)" ]; then
            MODAL_TOKEN_ID="$(op_cached modal-token-id 'op://4eeyrkqibibn7k4j6rz2fbzvxm/2sfxybjpv3c3ohzxhf5qeken4a/token_id')"
            MODAL_TOKEN_SECRET="$(op_cached modal-token-secret 'op://4eeyrkqibibn7k4j6rz2fbzvxm/2sfxybjpv3c3ohzxhf5qeken4a/token_secret')"
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
        pkgs._1password-cli
        pkgs.jq
        pkgs.curl
      ];
      text = ''
        if [ -n "''${GOG_ACCESS_TOKEN:-}''${GOG_HOME:-}" ]; then
          exec ${gogcliPkg}/bin/gog "$@"
        fi
        ${builtins.readFile ./agent-detect.sh}
        ${builtins.readFile ./agent-op-env.sh}
        item="$(op item get jjc6xu22cew46e6zpyfdsdjv3e --vault 4eeyrkqibibn7k4j6rz2fbzvxm --format json 2>/dev/null || true)"
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
          rt="$(jq -r '[.fields[] | select(.id == "credential")][0].value // empty' <<<"$item" | jq -r '.refresh_token // empty' 2>/dev/null || true)"
          client="$(op read 'op://4eeyrkqibibn7k4j6rz2fbzvxm/4x66lrvreiljbmepa6esgkyu2e/credential' 2>/dev/null || true)"
          cid="$(jq -r '.installed.client_id // .web.client_id // empty' <<<"$client" 2>/dev/null || true)"
          csec="$(jq -r '.installed.client_secret // .web.client_secret // empty' <<<"$client" 2>/dev/null || true)"
          if [ -n "$rt" ] && [ -n "$cid" ]; then
            resp="$(printf 'grant_type=refresh_token&client_id=%s&client_secret=%s&refresh_token=%s' "$cid" "$csec" "$rt" \
              | curl -s --max-time 30 --data @- https://oauth2.googleapis.com/token || true)"
            at="$(jq -r '.access_token // empty' <<<"$resp" 2>/dev/null || true)"
            expin="$(jq -r '.expires_in // 3600' <<<"$resp" 2>/dev/null || echo 3600)"
            if [ -n "$at" ]; then
              op item edit jjc6xu22cew46e6zpyfdsdjv3e --vault 4eeyrkqibibn7k4j6rz2fbzvxm \
                "access_token[concealed]=$at" "expires_at[text]=$((now + expin))" >/dev/null 2>&1 || true
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

    # gcloud, ALWAYS authed via 1Password (GCP SA key item in the AI Agent
    # vault). Replaces the brew gcloud-cli cask and the interactive-only op
    # plugin alias. The key JSON transits a 0600 mktemp file removed on exit
    # (same mechanism `op plugin run` uses internally).
    (pkgs.writeShellApplication {
      name = "gcloud";
      runtimeInputs = [ pkgs._1password-cli ];
      text = ''
        if [ -n "''${CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE:-}''${GOOGLE_APPLICATION_CREDENTIALS:-}" ]; then
          exec ${pkgs.google-cloud-sdk}/bin/gcloud "$@"
        fi
        ${builtins.readFile ./agent-detect.sh}
        ${builtins.readFile ./agent-op-env.sh}
        keyfile="$(mktemp "''${TMPDIR:-/tmp}/gcloud-key-XXXXXX")"
        trap 'rm -f "$keyfile"' EXIT
        if op read 'op://4eeyrkqibibn7k4j6rz2fbzvxm/iqywn6he6twhyonw3fhnqmot5i/credential' > "$keyfile" 2>/dev/null && [ -s "$keyfile" ]; then
          export CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE="$keyfile"
        fi
        ${pkgs.google-cloud-sdk}/bin/gcloud "$@"
      '';
    })
  ];
}
