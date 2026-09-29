# Xcode as an agent's build host: Xcode from the App Store, Apple's headless
# MCP server switched on, and the human steps that make simulators, signing
# and the agent grant real. Pairs with home/apple-agent.nix, which declares
# the `xcode` MCP server and re-exports Apple's agent skills per switch.
#
# Xcode 27 is the floor: `xcrun mcp-server` (headless) and `xcrun agent
# skills export` exist only from 27, and Xcode 27 needs macOS 26.6+. The
# activation below skips silently on older Xcode or bare Command Line Tools,
# so a host can enable this before the App Store download lands.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.xcode-agent;
  # "27.0" -> 27 ; "" (CLT only) -> 0
  xcodeMajor = ''
    xcode_major() {
      /usr/bin/xcodebuild -version 2>/dev/null | /usr/bin/awk 'NR==1{split($2,v,"."); print v[1]+0}'
    }
  '';
  # Approves the PENDING agent requests whose code signature is declared in
  # `approvedAgents`, and nothing else: no arguments, so a caller cannot
  # approve an id of its choosing. Xcode records a request when an agent's
  # first workspace call is refused; run this, then the agent retries.
  approve = pkgs.writeShellScriptBin "xcode-agent-approve" ''
    set -euo pipefail
    [ "$(/usr/bin/id -u)" -eq 0 ] || { echo "xcode-agent-approve: run with sudo" >&2; exit 1; }
    # mcp-server records which user the headless server belongs to from
    # sudo's variables; activation runs as plain root, so supply them.
    export SUDO_USER="''${SUDO_USER:-${cfg.user}}"
    export SUDO_UID="''${SUDO_UID:-$(/usr/bin/id -u ${lib.escapeShellArg cfg.user})}"
    export SUDO_GID="''${SUDO_GID:-$(/usr/bin/id -g ${lib.escapeShellArg cfg.user})}"
    trusted=${lib.escapeShellArg (builtins.toJSON cfg.approvedAgents)}
    ids=$(/usr/bin/xcrun mcp-server status --format json 2>/dev/null \
      | ${pkgs.jq}/bin/jq -r --argjson trusted "$trusted" '
          .permission.pendingAgentApprovals[]?
          | (.subject.agent._0.trust.signed // empty) as $s
          | select(any($trusted[]; .team == $s.teamIdentifier and .identifier == $s.signingIdentifier))
          | .id' || true)
    [ -n "$ids" ] || { echo "xcode-agent-approve: no pending request from a declared agent"; exit 0; }
    for id in $ids; do
      /usr/bin/xcrun mcp-server approve --always "$id" 2>&1 | /usr/bin/sed 's/^/xcode-agent-approve: /'
    done
  '';
in
{
  options.services.xcode-agent = {
    enable = lib.mkEnableOption "Xcode 27 plus Apple's MCP server for coding agents";

    user = lib.mkOption {
      type = lib.types.str;
      description = "Login user whose keychain, Xcode account and agent sessions this serves.";
    };

    approvedAgents = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            team = lib.mkOption {
              type = lib.types.str;
              description = "Apple team identifier the agent binary is signed by.";
            };
            identifier = lib.mkOption {
              type = lib.types.str;
              description = "Code-signing identifier of the agent binary.";
            };
          };
        }
      );
      default = [ ];
      example = [
        {
          team = "Q6L2SF6YDW";
          identifier = "com.anthropic.claude-code";
        }
      ];
      description = "Code signatures trusted to use Xcode's MCP server. Their pending requests are approved (durably) at activation and by `sudo xcode-agent-approve`, which the user may run without a password.";
    };

    allowedFolders = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "/Users/me/code" ];
      description = "Folders (with their subfolders) headless Xcode may serve workspaces from, granted at activation so no per-project prompt appears.";
    };
  };

  config = lib.mkIf cfg.enable {
    # nix-darwin puts `mas` on the brew-bundle PATH itself; the App Store
    # sign-in is the manual step below.
    homebrew.masApps.Xcode = 497799835;

    # Activation runs as root, so Xcode's license and first-launch component
    # install are codified here instead of a manual `sudo xcodebuild` step.
    # preActivation runs before the Homebrew phase, which refuses to run at
    # all while an installed Xcode's license is unaccepted (every switch used
    # to die at "Homebrew bundle..." after the App Store install). Both
    # xcodebuild checks exit 69 while pending and 0 once done.
    system.activationScripts.preActivation.text = lib.mkAfter ''
      if [ -d /Applications/Xcode.app ]; then
        /usr/bin/xcode-select -p 2>/dev/null | /usr/bin/grep -q '^/Applications/Xcode.app/' \
          || /usr/bin/xcode-select -s /Applications/Xcode.app/Contents/Developer
        if ! /usr/bin/xcodebuild -license check >/dev/null 2>&1; then
          echo "xcode-agent: accepting the Xcode license"
          /usr/bin/xcodebuild -license accept
        fi
        if ! /usr/bin/xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
          echo "xcode-agent: installing Xcode's first-launch components"
          /usr/bin/xcodebuild -runFirstLaunch
        fi
      fi
    '';

    # One-time root switch Apple documents as `sudo xcrun mcp-server enable`;
    # idempotent, and a no-op until Xcode 27 is the selected developer dir.
    system.activationScripts.postActivation.text = lib.mkAfter ''
      ${xcodeMajor}
      if [ "$(xcode_major)" -ge 27 ]; then
        # mcp-server refuses plain root: it records WHICH user the headless
        # server belongs to from sudo's variables, so supply them.
        mcp_server() {
          SUDO_USER=${lib.escapeShellArg cfg.user} \
          SUDO_UID=$(/usr/bin/id -u ${lib.escapeShellArg cfg.user}) \
          SUDO_GID=$(/usr/bin/id -g ${lib.escapeShellArg cfg.user}) \
            /usr/bin/xcrun mcp-server "$@" 2>&1 | /usr/bin/sed "s/^/xcode-agent: $1: /" || true
        }
        mcp_server enable
        ${lib.concatMapStringsSep "\n" (
          f: "mcp_server allow-folder --always ${lib.escapeShellArg f}"
        ) cfg.allowedFolders}
        ${lib.optionalString (cfg.approvedAgents != [ ]) "${approve}/bin/xcode-agent-approve || true"}
        mcp_server status
      else
        echo "xcode-agent: Xcode 27 not installed yet, skipping mcp-server enable"
      fi
    '';

    # The sanctioned exit for an agent whose first call was refused: approve
    # declared signatures only, no password, no switch.
    environment.systemPackages = lib.mkIf (cfg.approvedAgents != [ ]) [ approve ];
    security.sudo.extraConfig = lib.mkIf (cfg.approvedAgents != [ ]) ''
      ${cfg.user} ALL=(root) NOPASSWD: /run/current-system/sw/bin/xcode-agent-approve
    '';

    manual.steps = {
      app-store-signin = {
        title = "Sign into the App Store and install Xcode from it";
        owner = "xcode-agent";
        desktop = true;
        body = ''
          Over Screen Sharing: App Store app → Sign In with the owner's Apple
          ID (password + 2FA), then search Xcode → Get (about 12 GB). The
          `masApps` entry owns it from then on (updates, zap protection), but
          it cannot do the first install: App Store installs need root since
          mas 4 and the switch runs `brew bundle` as the user with no tty, so
          `mas install` fails with "sudo: a password is required" until the
          app exists.
        '';
        verify = "test -d /Applications/Xcode.app";
      };

      ios-simulator-runtime = {
        title = "Download the iOS simulator runtime";
        owner = "xcode-agent";
        body = ''
          `xcodebuild -downloadPlatform iOS` (about 8 GB; Xcode plus one
          runtime leaves roughly 20 GB free on the mini's disk). Agents test
          on simulators from this runtime; `just run` and the Xcode MCP
          device-interaction tools need it.
        '';
        verify = "xcrun simctl list runtimes 2>/dev/null | grep -q 'iOS 27'";
        redo = "after every major Xcode update (new iOS runtime)";
      };

      xcode-account = {
        title = "Sign Xcode into the developer team";
        owner = "xcode-agent";
        desktop = true;
        body = ''
          Xcode → Settings → Accounts → add the developer Apple ID. Debug
          automatic signing (`just build`, readable device logs) needs it;
          Release Ad Hoc signing does not.
        '';
      };

      apple-distribution-cert = {
        title = "Import the Apple Distribution certificate into the login keychain";
        owner = "xcode-agent";
        body = ''
          Release Ad Hoc builds (`just deploy`) sign with this identity. The
          certificate lives in the Apple Signing vault; on the mini open an
          `op-unlock request "Apple Distribution cert import"` window first.

          ```bash
          op-personal read "op://xxbixvqoaicfykrbte6oh57ahq/fjlhndynlojmvcvhcei6qblsxm/p12_base64" \
            | base64 -d > "$TMPDIR/dist.p12"
          security import "$TMPDIR/dist.p12" -k ~/Library/Keychains/login.keychain-db \
            -P "$(op-personal read 'op://xxbixvqoaicfykrbte6oh57ahq/fjlhndynlojmvcvhcei6qblsxm/password')" \
            -T /usr/bin/codesign
          rm -f "$TMPDIR/dist.p12"
          ```
        '';
        verify = "security find-identity -v -p codesigning | grep -q 'Apple Distribution'";
        redo = "when `apple-signing renew-distribution` rotates the certificate";
      };

      xcode-mcp-agent-grant = {
        title = "Approve an agent that is not declared in approvedAgents";
        owner = "xcode-agent";
        body = ''
          Declared signatures (`services.xcode-agent.approvedAgents`) need no
          human: an agent whose first workspace call was refused runs `sudo
          xcode-agent-approve` (passwordless) and retries. Anything else -
          an unsigned binary, a new agent - is approved by hand, or added to
          the option:

          ```bash
          xcrun mcp-server status          # Pending approvals: agent <id>: <name> - signed <team> <identifier>
          sudo xcrun mcp-server approve --always <id>
          ```

          Unsigned binaries only get 24 hours. Never approve a wrapper such
          as `timeout` in the agent's place.
        '';
      };
    };
  };
}
