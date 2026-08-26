{ pkgs, cherri, nix-openclaw-tools, ... }:

# Portable dev toolbox shared by BOTH hosts — everything needed to clone,
# build, and deploy projects from either machine. Laptop-only tooling
# (Apple build chain, GUI helpers, fonts) stays in home/macbook-air.nix.
# Exported via homeModules; consumers must pass `cherri` and
# `nix-openclaw-tools` through extraSpecialArgs (like vscode.nix's input).
let
  # gogcli from the openclaw flake — tracks upstream releases; nixpkgs' copy
  # lags months behind at gog's weekly cadence.
  gogcliPkg = nix-openclaw-tools.packages.${pkgs.stdenv.hostPlatform.system}.gogcli;
in
{
  home.packages = [
    pkgs.bun
    pkgs.exiftool
    pkgs.ffmpeg
    pkgs.oci-cli
    pkgs.pnpm
    pkgs.terraform # unfree (BSL) — allowed in each host's predicate
    pkgs.wrangler # brew name: cloudflare-wrangler
    pkgs.yt-dlp
    # Cherri compiler for the ios-shortcuts project (flake input; not in nixpkgs).
    cherri.packages.${pkgs.stdenv.hostPlatform.system}.default
    # gog (Google CLI), wrapped with 1P-ONLY credential storage: gog itself
    # never sees a refresh token and nothing credential-shaped touches disk.
    # The wrapper owns the OAuth refresh: the "AI Agent Gog Token Export"
    # item holds the refresh token (credential field, `gog auth tokens
    # export` JSON) plus a cached access_token/expires_at pair the wrapper
    # writes back after each refresh; "AI Agent Gog OAuth Client" holds the
    # client JSON. Fast path (access token still valid) = ONE op call, no
    # Google round-trip; slow path (~hourly) = curl refresh + 1P writeback.
    # gog runs in --access-token mode throughout (bypasses stored tokens).
    # The macOS keychain backend stays banned: structurally broken for nix
    # binaries (adhoc-signed, store path changes each rebuild → ACL prompt
    # flood). Caller-set GOG_ACCESS_TOKEN or GOG_HOME bypasses everything
    # (the consent bootstrap uses GOG_HOME; see the gog skill).
    (pkgs.writeShellApplication {
      name = "gog";
      runtimeInputs = [ pkgs._1password-cli pkgs.jq pkgs.curl ];
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
    # vault) — same paradigm as the gh wrapper in scripts.nix. Replaces the
    # brew gcloud-cli cask and the interactive-only op plugin alias so
    # scripts/launchd/agent shells are authed too. The key JSON transits a
    # 0600 mktemp file removed on exit (same mechanism `op plugin run` uses
    # internally).
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
    # memo (Apple Notes CLI, antoniorodr/memo) — needed by the apple-notes /
    # triage-apple-notes agent skills. Not in nixpkgs, and its brew formula's
    # python was broken, so run it uv-style: uvx resolves from git once and
    # reuses the cached env (refresh = `uvx --refresh --from … memo`).
    (pkgs.writeShellApplication {
      name = "memo";
      runtimeInputs = [ pkgs.uv ];
      text = ''
        exec uvx --from git+https://github.com/antoniorodr/memo memo "$@"
      '';
    })
  ];
}
