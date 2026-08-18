{ pkgs, lib, config, ... }:

# Chrome extension keyboard shortcuts (no policy/API exists for them - they
# live only in the profile's Preferences JSON under extensions.commands, so a
# reinstall/reload of an extension wipes them). This merges the declared
# shortcuts back in on every switch. Chrome rewrites Preferences on quit, so
# the merge is skipped while Chrome is running - it converges on the next
# switch with Chrome quit, and takes effect when Chrome next starts.
let
  cfg = config.chrome.extensionShortcuts;
  jq = "${pkgs.jq}/bin/jq";
  commandsJson = builtins.toJSON cfg.commands;
in
{
  options.chrome.extensionShortcuts = {
    profile = lib.mkOption {
      type = lib.types.str;
      default = "Default";
      description = "Profile directory name under ~/Library/Application Support/Google/Chrome.";
    };
    commands = lib.mkOption {
      type = lib.types.attrsOf lib.types.attrs;
      default = { };
      example = {
        "mac:Command+Shift+C" = {
          command_name = "1copy-highlighted-tabs";
          extension = "micdllihgoppmejpecmkilggmaagfdmb";
          global = false;
        };
      };
      description = "extensions.commands entries to enforce, keyed by key combo.";
    };
  };

  config = lib.mkIf (cfg.commands != { }) {
    home.activation.chromeExtensionShortcuts = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      prefs="$HOME/Library/Application Support/Google/Chrome/${cfg.profile}/Preferences"
      want='${commandsJson}'
      if [ -f "$prefs" ]; then
        if ${jq} -e --argjson want "$want" \
             '(.extensions.commands // {}) as $have | $want | to_entries | all($have[.key] == .value)' \
             "$prefs" >/dev/null; then
          : # already set
        elif pgrep -x "Google Chrome" >/dev/null; then
          echo "chrome.extensionShortcuts: Chrome is running; skipping Preferences merge (re-switch with Chrome quit)" >&2
        else
          ${jq} --argjson want "$want" \
            '.extensions.commands = (.extensions.commands // {}) + $want' \
            "$prefs" > "$prefs.tmp" && mv "$prefs.tmp" "$prefs"
        fi
      fi
    '';
  };
}
