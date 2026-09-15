{ config, lib, ... }:

# User-side facts for the compliance skill's browser collector (agent-config
# skills/compliance): which synced Chrome session is the phone, and, on the
# host that runs the agent Chrome itself, its local CDP port. The skill reads
# ~/.config/compliance/connections.json; exceptions.json in the same dir stays
# runtime state the skill manages.
let
  cfg = config.compliance.browser;
in
{
  options.compliance.browser = {
    phoneSession = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Stable foreign_session.id of the phone in Chrome's synced tabs.";
    };
    port = lib.mkOption {
      type = lib.types.nullOr lib.types.port;
      default = null;
      description = "Local CDP port of the agent Chrome when it runs on this host (otherwise the collector tunnels to CHROME_CONTROL_HOST).";
    };
  };

  config.xdg.configFile."compliance/connections.json".text = builtins.toJSON {
    browser = lib.filterAttrs (_: v: v != null) {
      phone-session = cfg.phoneSession;
      port = cfg.port;
    };
  };
}
