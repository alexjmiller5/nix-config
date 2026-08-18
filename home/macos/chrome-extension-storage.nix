{ pkgs, lib, config, ... }:

# chrome.storage.local values for extensions (settings with no export/sync -
# e.g. Tab Copy's custom formats - live only in the profile's per-extension
# LevelDB, so a reinstall wipes them). Enforces the declared keys at every
# switch; undeclared keys (stats, caches) are left alone. Chrome holds the DB
# lock while running, so the write is skipped then - it converges on a later
# switch with Chrome quit. Declared values are authoritative: a change made in
# the extension's UI reverts at the next switch unless mirrored here.
let
  cfg = config.chrome.extensionStorage;
  py = pkgs.python3.withPackages (ps: [ ps.plyvel ]);
  storageJson = builtins.toJSON cfg.storage;
in
{
  options.chrome.extensionStorage = {
    profile = lib.mkOption {
      type = lib.types.str;
      default = "Default";
      description = "Profile directory name under ~/Library/Application Support/Google/Chrome.";
    };
    storage = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = { };
      example = {
        micdllihgoppmejpecmkilggmaagfdmb.orderedFormatIds = [ "custom-9hVL4q" ];
      };
      description = "Extension id -> chrome.storage.local keys to enforce (values are JSON-serializable nix values).";
    };
  };

  config = lib.mkIf (cfg.storage != { }) {
    home.activation.chromeExtensionStorage = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      CHROME_EXT_STORAGE_WANT=${lib.escapeShellArg storageJson} \
      CHROME_EXT_STORAGE_BASE="$HOME/Library/Application Support/Google/Chrome/${cfg.profile}/Local Extension Settings" \
      ${py}/bin/python3 - <<'PYEOF'
      import json, os, subprocess, sys
      import plyvel

      want = json.loads(os.environ["CHROME_EXT_STORAGE_WANT"])
      base = os.environ["CHROME_EXT_STORAGE_BASE"]
      running = subprocess.run(["/usr/bin/pgrep", "-x", "Google Chrome"],
                               capture_output=True).returncode == 0
      for ext, keys in want.items():
          path = os.path.join(base, ext)
          if not os.path.isdir(path):
              continue  # extension not installed (yet); converge later
          if running:
              print("chrome.extensionStorage: Chrome is running; skipping "
                    + ext + " (re-switch with Chrome quit)", file=sys.stderr)
              continue
          try:
              db = plyvel.DB(path)
          except Exception as e:
              print("chrome.extensionStorage: cannot open " + ext + ": "
                    + str(e), file=sys.stderr)
              continue
          try:
              for k, v in keys.items():
                  cur = db.get(k.encode())
                  if cur is None or json.loads(cur.decode()) != v:
                      db.put(k.encode(),
                             json.dumps(v, separators=(",", ":")).encode())
          finally:
              db.close()
      PYEOF
    '';
  };
}
