{ username, pkgs, ... }:

# Shared home-manager base for every host. The package list lives in
# cli-tools.nix (exported via homeModules); this file adds only the
# machine-identity bits external consumers set themselves.
# machine-vault-git requires its options set per host; agent-config-links
# and op-wrappers are zero-config (op-wrappers needs nix-openclaw-tools in
# extraSpecialArgs).
{
  imports = [
    ../modules/manual-steps.nix
    ./macos/finder.nix
    ./git.nix
    ./git-signing.nix
    ./git-hooks.nix
    ./scripts.nix
    ./cli-tools.nix
    ./mcp.nix
    ./op-wrappers.nix
    ./agent-config-links.nix
    ./claude-plugins.nix
    ./codex.nix
    ./machine-vault-git.nix
    ./people-sync-operator.nix
  ];

  opAuth.vaultId = "4eeyrkqibibn7k4j6rz2fbzvxm";

  # Life supplies the installed background runner and its CLI toggle.
  # Interactive agent auth remains separate; background credentials are
  # configured through `life background enable` on each device.
  lifeData = {
    enable = true;
  };

  home.stateVersion = "25.05";
  home.username = username;
  home.homeDirectory = "/Users/${username}";

  # Human steps nix cannot do (rendered into MANUAL-<host>.md; verified by manual-check).
  manual.steps = {
    life-background-sync = {
      title = "Life login and background sync";
      owner = "life-data";
      desktop = true;
      body = ''
        Nix installs Life, its configuration and the login-time background runner
        through `home/common.nix` and Life's Home Manager module. It does **not**
        restore the local Keychain entry or the user's sync toggle. A fresh machine
        starts with sync off; a normal Nix rebuild preserves an existing toggle.

        After the machine bootstrap, sign the Mac into Life from its logged-in desktop
        Terminal (over Screen Sharing on the headless mini):

        ```sh
        life login --name "<this Mac's name>"
        ```

        The command opens the Life browser sign-in flow. Complete the email one-time
        code challenge and approve the displayed device. Life stores the scoped device
        credential in macOS Keychain. This login does not enable background sync.

        Then opt into background sync explicitly:

        ```sh
        life background enable
        ```

        If the browser did not open automatically, copy the URL printed by `life login`
        into the signed-in browser. Run enrollment and the enable command in a Terminal
        attached to the logged-in desktop so macOS can authorize Keychain access. Do
        not recover or copy a Life token through a machine vault, a service account, a
        shell literal, a file, Git or the Nix store.

        1. Let the background runner initialize and download the replica, then run:

           ```sh
           life background status
           ```

           Verify `enabled: true`, `running: true`, a populated `last_success`,
           `last_error: null` and zero rejected rows in `stats`. `enabled` alone is
           not proof that data synced. Large first downloads take longer. Do not
           start a concurrent `life sync` while the background round is running.
           Check status again after logout/login to verify automatic startup.

        If both Macs are lost, install Nix from GitHub and enroll each replacement
        through the Life browser sign-in flow. The surviving Life hub supplies synced
        schema, tables and history. Edits that never reached the hub need an
        independent backup; Nix cannot recover them. This procedure assumes the hub is
        healthy and reachable.
      '';
      verify = "life background status | jq -e '.enabled and .running' >/dev/null";
      redo = "on a replacement machine";
    };
  };

}
