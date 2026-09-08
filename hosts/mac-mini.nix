{
  config,
  pkgs,
  lib,
  username,
  ...
}:

# Shared base (stateVersion, unfree predicate, /etc/nix-darwin, brew zap, …)
# comes from modules/darwin-base.nix via mkHost.
let
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
  peopleSyncCredential = pkgs.writeShellScript "people-sync-credential" ''
    set -euo pipefail
    case "$1" in
      ${lib.concatStringsSep "\n      " (lib.mapAttrsToList (platform: id: "${platform}) item=${id} ;;") peopleSyncLogins)}
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
  # Newest 6-8 digit code texted to this Mac in the last 10 minutes whose
  # message names the platform ($1); prints nothing when none has arrived.
  peopleSyncSmsCode = pkgs.writeShellScript "people-sync-sms-code" ''
    set -euo pipefail
    since="$(/bin/date -u -v-10M +%Y-%m-%dT%H:%M:%SZ)"
    /opt/homebrew/bin/imsg search --query code --limit 30 --json \
      | ${jq} -r --arg since "$since" --arg p "$1" \
          'select(.is_from_me == false and .created_at > $since and ((.text // "") | ascii_downcase | contains($p)))
           | (.text | [match("\\b[0-9]{6,8}\\b")] | .[0].string // empty)' \
      | head -n 1
  '';
  # Same for email: newest thread from the last 15 minutes mentioning the
  # platform, first 6-8 digit run in its body or snippet.
  peopleSyncEmailCode = pkgs.writeShellScript "people-sync-email-code" ''
    set -euo pipefail
    gog=/etc/profiles/per-user/${username}/bin/gog
    id="$("$gog" gmail search "newer_than:15m $1" --max 1 -j 2>/dev/null | ${jq} -r '.threads[0].id // empty')"
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
  ];
  # iMessage CLI - the people-sync SMS-code command reads texted 2FA codes
  # from this Mac's Messages (it is signed in). Not in nixpkgs.
  homebrew.brews = [ "steipete/tap/imsg" ];

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
  };
  services.callhistory-backup = {
    enable = true;
    user = username;
    # WhatsApp cask + keep-alive come from the module (its runtime dep for
    # third-party call durations). One-time QR link — README §6.
    installWhatsApp = true;
  };

  # Daily social-profile scraping into life-data (the people-sync flake's
  # module): one dedicated Chrome profile per site, human-paced, logins
  # automated through the three commands above. Nothing here is the app's
  # business beyond "run this command" - see the people-sync README.
  services.people-sync-scrape = {
    enable = true;
    user = username;
    platforms = [
      "facebook"
      "instagram"
      "linkedin"
      "venmo"
      "spotify"
      "partiful"
    ];
    credentialCommand = "${peopleSyncCredential}";
    smsCodeCommand = "${peopleSyncSmsCode}";
    emailCodeCommand = "${peopleSyncEmailCode}";
  };

  # The mini's ONE agenix secret: the mac-mini-machine 1P service-account
  # token (read-only on the "Mac Mini" vault). Every other secret — e.g. the
  # git PAT — lives in that vault, fetched at runtime via op read; see
  # secrets/secrets.nix.
  age.secrets.machine-sa = {
    file = ../secrets/machine-sa-mini.age;
    owner = username;
  };

}
