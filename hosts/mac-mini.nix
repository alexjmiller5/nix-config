{
  config,
  pkgs,
  lib,
  username,
  inputs,
  ...
}:

# Shared base (stateVersion, unfree predicate, /etc/nix-darwin, brew zap, …)
# comes from modules/darwin-base.nix via mkHost.
let
  peopleSync = inputs.people-sync.packages.${pkgs.stdenv.hostPlatform.system}.default;
  op = "${pkgs._1password-cli}/bin/op";
  jq = "${pkgs.jq}/bin/jq";
  # People Sync: the scrape job signs into each site with a login copy held
  # in the project vault, read by the people-sync-ci service account. That
  # SA's token sits in this machine's vault (Mac Mini), reachable through
  # the machine SA - the same two-hop pattern as the agent token file.
  peopleSyncVault = "ug25zl4cfxnyk7rnwkyhea752i";
  peopleSyncCiTokenRef = "op://g532a3e4zyqqrc7b2v3lhv4zmy/yvzwnlyp5yt2z5fmslh3u7lkk4/password";
  peopleSyncLogins = {
    facebook = "hrhy367724zrscj7pu5o33ko6i";
    instagram = "dl57v3ospxj7ilto26zizrdf3e";
    linkedin = "kcydj6vtwovqmjowc4zvwv46my";
    venmo = "zdlpzwotyr6gmcdwqgsgbkorma";
    spotify = "rydldw3mn7znxtq6kgr6gqe74e";
    partiful = "4t5fqj3c6lsf6wn3p6wqiht4ja";
  };
  # $1 = platform. Prints {"username","password","totp"} (totp = current code
  # or null) - the contract in the people-sync README.
  # Screentime Dashboard: the mini pushes rebuilt Screen Time series to the
  # dashboard Worker through Cloudflare Access with a service token that
  # lives in this machine's vault - one hop via the machine SA, read only
  # when a sync actually runs (never by the 60s poll).
  screentimeDashboardCredential = pkgs.writeShellScript "screentime-dashboard-credential" ''
    set -euo pipefail
    OP_SERVICE_ACCOUNT_TOKEN="$(/bin/cat ${config.age.secrets.machine-sa.path})" \
      ${op} item get oeet73ymsgiwoozsfsvu2rprku --vault g532a3e4zyqqrc7b2v3lhv4zmy --format json \
      | ${jq} -c '{
          clientId: ([.fields[] | select(.label == "client_id") | .value] | first),
          clientSecret: ([.fields[] | select(.label == "client_secret") | .value] | first)
        }'
  '';
  peopleSyncCredential = pkgs.writeShellScript "people-sync-credential" ''
    set -euo pipefail
    case "$1" in
      ${lib.concatStringsSep "\n      " (
        lib.mapAttrsToList (platform: id: "${platform}) item=${id} ;;") peopleSyncLogins
      )}
      *) echo "no login item for platform $1" >&2; exit 1 ;;
    esac
    export OP_SERVICE_ACCOUNT_TOKEN="$(OP_SERVICE_ACCOUNT_TOKEN="$(/bin/cat ${config.age.secrets.machine-sa.path})" \
      ${op} read '${peopleSyncCiTokenRef}')"
    ${op} item get "$item" --vault ${peopleSyncVault} --format json | ${jq} -c '{
      username: ([.fields[] | select(.id == "username") | .value] | first),
      password: ([.fields[] | select(.id == "password") | .value] | first),
      totp: ([.fields[] | select(.type == "OTP") | .totp] | first)
    }'
  '';
  # Newest 6-8 digit code texted to this Mac after the request time (or
  # within 10 minutes) whose message names the platform ($1); prints
  # nothing when none has arrived.
  peopleSyncSmsCode = pkgs.writeShellScript "people-sync-sms-code" ''
    set -euo pipefail
    # people-sync hands over the moment it asked for the code; fall back to a
    # short window for other callers.
    since="''${PEOPLE_SYNC_CODE_AFTER:-$(/bin/date -u -v-10M +%Y-%m-%dT%H:%M:%SZ)}"
    /opt/homebrew/bin/imsg search --query code --limit 30 --json \
      | ${jq} -r --arg since "$since" --arg p "$1" \
          'select(.is_from_me == false and .created_at > $since and ((.text // "") | ascii_downcase | contains($p)))
           | (.text | [match("\\b[0-9]{6,8}\\b")] | .[0].string // empty)' \
      | head -n 1
  '';
  # Same for email: newest thread after the request time (or within 15
  # minutes) mentioning the platform, first 6-8 digit run in its body or
  # snippet.
  peopleSyncEmailCode = pkgs.writeShellScript "people-sync-email-code" ''
    set -euo pipefail
    gog=/etc/profiles/per-user/${username}/bin/gog
    since="''${PEOPLE_SYNC_CODE_AFTER:-$(/bin/date -u -v-15M +%Y-%m-%dT%H:%M:%SZ)}"
    id="$("$gog" gmail search "newer_than:1h $1" --max 5 -j 2>/dev/null \
      | ${jq} -r --arg since "$since" '[.threads[] | select(.internalDateIso > $since)][0].id // empty')"
    [ -n "$id" ] || exit 0
    "$gog" gmail get "$id" -j 2>/dev/null \
      | ${jq} -r '((.body // "") + " " + (.message.snippet // "")) | [match("\\b[0-9]{6,8}\\b")] | .[0].string // empty' \
      | head -n 1
  '';
in
{
  # Headless box: never sleep, come back after power loss.
  power.sleep.computer = "never";
  power.sleep.display = "never";
  power.restartAfterPowerFailure = true;

  # Headless tailscaled (no GUI app). One-time join after first switch:
  #   sudo tailscale up --auth-key=<oauth-minted key, tag:oauth-generated> --hostname=mac-mini
  services.tailscale.enable = true;

  # trusted = true feeds Homebrew's tap-trust store at activation.
  homebrew.taps = [
    {
      name = "steipete/tap";
      trusted = true;
    }
    {
      name = "rjyo/moshi";
      trusted = true;
    }
  ];
  homebrew.brews = [
    # iMessage CLI - the people-sync SMS-code command reads texted 2FA codes
    # from this Mac's Messages (it is signed in). Not in nixpkgs.
    "steipete/tap/imsg"
    # Moshi (phone terminal) agent daemon: surfaces Claude Code sessions on
    # this Mac in the Moshi app (inbox, waiting-state pushes, diffs). Runs as
    # a brew launchd service. One-time pairing + hook install in
    # MANUAL-mac-mini.md §6; the Claude Code hooks it wants live in
    # agent-config's settings.json (nix-managed, read-only here).
    {
      name = "rjyo/moshi/moshi-hook";
      start_service = true;
    }
  ];

  # GUI apps that aren't packaged well in nixpkgs on macOS.
  homebrew.casks = [
    # @latest tracks releases faster than the plain cask; fable-5-1 needs >= 2.1.251
    "claude-code@latest"
    # ntn — home/ai-agent.nix's host-layer sibling (not in nixpkgs).
    "notion-cli"
    # Browser for agent-driven web work (chrome-control / web-recon).
    "google-chrome"
  ];

  # Weekly Apple-data snapshots (Sun 05:00 / 05:05). Each module installs a
  # signed .app + launchd agent; the one manual step per app is a Full Disk
  # Access grant (README §6). Output lands in iCloud-synced ~/Documents.
  services.screentime-backup = {
    enable = true;
    user = username;
    # After every snapshot (weekly, or kicked by a dashboard refresh) rebuild
    # and push the dashboard's series - inside the FDA-holding backup process.
    postRun = config.services.screentime-ingest.syncCommand;
    # A dashboard "rebuild" should set a flag so the agent skips the snapshot,
    # but neither input defines it yet (screentime-backup has no skipDumpFlag
    # option; screentime-ingest exposes no such path), so the line below does
    # not evaluate and takes the whole mini config with it. Re-enable once both
    # modules ship the option and the flake inputs are bumped.
    # skipDumpFlag = config.services.screentime-ingest.skipDumpFlag;
  };
  services.screentime-ingest = {
    enable = true;
    user = username;
    url = "https://screentime-dashboard.nqipomyrjb.workers.dev";
    credentialCommand = "${screentimeDashboardCredential}";
  };
  services.callhistory-backup = {
    enable = true;
    user = username;
    # WhatsApp cask + keep-alive come from the module (its runtime dep for
    # third-party call durations). One-time QR link — README §6.
    installWhatsApp = true;
  };

  # The one browser every agent job on this Mac drives (modules/agent-chrome.nix):
  # a headed Chrome on its own data dir, remote debugging on 9222, started at
  # login. Logins done in its window - by a job or by Alex over Screen
  # Sharing - persist for everything that attaches later.
  services.agent-chrome = {
    enable = true;
    user = username;
    # Claude in Chrome: its tabGroups permission is what chrome-control's
    # cdp-group.mjs borrows to give every agent session its own tab group.
    # Sign-in is manual (MANUAL-mac-mini.md).
    extensions = [ "fcoeoabgfenejglbffodgkkbkcdhcgfn" ];
  };

  # people-sync on this Mac: an ad-hoc tool an agent drives with Alex in the
  # loop (the people-review skill), never a schedule. `people-sync-mini`
  # wraps the CLI with this machine's wiring - the shared Chrome endpoint
  # and the three commands above (run as `sh -c "<cmd>" people-sync-login
  # <platform>`, so the platform is `$1` of the command string).
  environment.systemPackages = [
    peopleSync
    (pkgs.writeShellScriptBin "people-sync-mini" ''
      export PEOPLE_SYNC_CDP_ENDPOINT="127.0.0.1:${toString config.services.agent-chrome.port}"
      export PEOPLE_SYNC_CREDENTIAL_COMMAND='${peopleSyncCredential} "$1"'
      export PEOPLE_SYNC_SMS_CODE_COMMAND='${peopleSyncSmsCode} "$1"'
      export PEOPLE_SYNC_EMAIL_CODE_COMMAND='${peopleSyncEmailCode} "$1"'
      # R2 photo uploads: the project ENV item, read with the same CI token.
      ci="$(OP_SERVICE_ACCOUNT_TOKEN="$(/bin/cat ${config.age.secrets.machine-sa.path})" \
        ${op} read '${peopleSyncCiTokenRef}')"
      export CF_API_TOKEN="$(OP_SERVICE_ACCOUNT_TOKEN="$ci" ${op} read 'op://${peopleSyncVault}/5xs6y3x5sxkhmvbjlredlpk7oi/CF_API_TOKEN')"
      unset ci
      state="$HOME/.local/state/people-sync"
      mkdir -p "$state"
      cd "$state"
      exec ${peopleSync}/bin/people-sync "$@"
    '')
  ];

  # The mini's ONE agenix secret: the mac-mini-machine 1P service-account
  # token (read-only on the "Mac Mini" vault). Every other secret — e.g. the
  # git PAT — lives in that vault, fetched at runtime via op read; see
  # secrets/secrets.nix.
  age.secrets.machine-sa = {
    file = ../secrets/machine-sa-mini.age;
    owner = username;
  };

}
