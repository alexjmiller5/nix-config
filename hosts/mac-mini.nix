{
  config,
  pkgs,
  username,
  inputs,
  ...
}:

# Shared base (stateVersion, unfree predicate, /etc/nix-darwin, brew zap, …)
# comes from modules/darwin-base.nix via mkHost.
let
  peopleSync = inputs.people-sync.packages.${pkgs.stdenv.hostPlatform.system}.default;
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
    # iMessage CLI for operator use. Not in nixpkgs.
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
    # nixpkgs lags upstream by several releases; see home/codex.nix.
    "codex"
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
    skipDumpFlag = config.services.screentime-ingest.skipDumpFlag;
  };
  services.screentime-ingest = {
    enable = true;
    user = username;
    url = "https://screentime-dashboard.nqipomyrjb.workers.dev";
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

  # People Sync is operator-invoked. Chrome owns its saved site sessions;
  # the caller supplies dedicated file/Notion credentials when needed.
  environment.systemPackages = [
    peopleSync
    (pkgs.writeShellScriptBin "people-sync-mini" ''
      set -euo pipefail
      export PEOPLE_SYNC_CDP_ENDPOINT="127.0.0.1:${toString config.services.agent-chrome.port}"
      state="$HOME/.local/state/people-sync"
      mkdir -p "$state"
      cd "$state"
      exec ${peopleSync}/bin/people-sync "$@"
    '')
  ];

  # The mini's ONE agenix secret: the mac-mini-machine 1P service-account
  # token (read-only on the "Mac Mini" vault), used only by explicit initial
  # bootstrap commands; see secrets/secrets.nix.
  age.secrets.machine-sa = {
    file = ../secrets/machine-sa-mini.age;
    owner = username;
  };

}
