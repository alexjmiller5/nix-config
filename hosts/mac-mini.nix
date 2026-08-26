{ config, pkgs, lib, username, ... }:

{
  system.stateVersion = 6;
  system.primaryUser = username;
  nixpkgs.hostPlatform = "aarch64-darwin";

  # The 1Password CLI (op) — agent shells (home/ai-agent.nix) and the
  # notion-finance-sync sync — is unfree.
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [ "1password-cli" ];

  # Determinate Nix manages the nix daemon itself; nix-darwin must not.
  nix.enable = false;

  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
  };

  # Headless box: never sleep, come back after power loss.
  power.sleep.computer = "never";
  power.sleep.display = "never";
  power.restartAfterPowerFailure = true;

  environment.systemPackages = with pkgs; [
    git
    just
  ];

  # Headless tailscaled (no GUI app). One-time join after first switch:
  #   sudo tailscale up --auth-key=<oauth-minted key, tag:oauth-generated> --hostname=mac-mini
  services.tailscale.enable = true;

  # GUI apps that aren't packaged well in nixpkgs on macOS.
  # Homebrew itself is installed by nix-homebrew (see flake.nix).
  # NB: the notion-finance-sync module adds the `google-chrome` cask; with
  # cleanup = "zap" that's fine — declared casks merge across modules.
  homebrew = {
    enable = true;
    casks = [
      "claude-code"
      # ntn — home/ai-agent.nix's host-layer sibling (not in nixpkgs).
      "notion-cli"
      # Normally declared by the notion-finance-sync module — pinned here while
      # the sync is paused so zap doesn't uninstall Chrome (bank session
      # profiles keep their browser). Drop when the sync is re-enabled.
      "google-chrome"
    ];
    onActivation.cleanup = "zap"; # remove anything not declared here
  };

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

  # The mini's ONE agenix secret: the mac-mini-machine 1P service-account
  # token (read-only on the "Mac Mini" vault). Every other secret — the git
  # PAT, the finance SA token — lives in that vault, fetched at runtime via
  # op read; see secrets/secrets.nix.
  age.secrets.machine-sa = {
    file = ../secrets/machine-sa-mini.age;
    owner = username;
  };

  # Daily bank -> Notion sync. The module builds the app (uv2nix) and installs
  # Chrome + the `op` CLI + a launchd agent — no checkout, no uv sync. `settings`
  # is the (non-secret) config.toml, rendered into the store. Secrets stay in
  # 1Password; remaining manual setup (Full Disk Access, first per-bank login)
  # is in the notion-finance-sync repo's docs/DEPLOY.md. Its own SA token is
  # read from the machine vault at job start (tokenOpRef, IDs not names).

  services.notion-finance-sync = {
    # PAUSED 2026-08-10 while the bank flows get fixed (bofa/fidelity OTP
    # element drift, everbank already-logged-in path, etrade re-login) — it
    # was failing every 3:30 run. Re-enable + drop the pinned google-chrome
    # cask above when the app is fixed.
    enable = false;
    user = username;
    hour = 3;
    minute = 30;
    tokenOpRef = "op://g532a3e4zyqqrc7b2v3lhv4zmy/dkefgdiep33rztuh7kzeokq3by/password";
    tokenOpAuthFile = config.age.secrets.machine-sa.path;
    settings = {
      # gmail address + Bilt phone come from 1Password ("Personal Identifiers"
      # in the project vault) — personal identifiers stay out of this public repo.
      notion = {
        transactions_database_id = "34603953a8af801fac1cf9720fa11d64";
        transactions_data_source_id = "34603953-a8af-806e-bd83-000b5b921780";
        tasks_data_source_id = "77ef5074-aa23-468a-b5fb-2692e78184db";
        property_ids = {
          NAME = "title"; AMOUNT = "%40%3DeX"; DATE = "apGe"; STATUS = "bNqL";
          SOURCE_ID = "c%5BvI"; SOURCE_ACCOUNT_ID = "TatA"; PAYEE = "G%5DBY";
          MEMO = "qpd%5B"; BANK_CATEGORY = "Loz%7B"; CATEGORY = "Hj%7CJ";
          BANK = "INs%3B"; CREDIT_CARD_ACCOUNT = "%3E%7D%7Bt"; CARD_NETWORK = "Xx%7Cq";
          ACCOUNT_TYPE = "dJ%7C%7C"; ACCOUNT_NAME = "KND%3D"; CALCULATED_REWARDS = "GVVr";
          TRUE_REWARDS = "_U~%40"; REWARDS_TYPE = "Pz%5Eo"; BILT_POINTS = "t%5DBn";
          BILT_PARTNER = "%3Aycu"; EXCLUDED = "%5EepD"; QUANTITY = "JXmA";
          TICKER = "%3BmS%3E"; PRICE_PER_SHARE = "efsI"; REVIEW_STATUS = "%3E%7BtH";
          RELEASE_DATE = "yUd%7D"; NET_AMOUNT = "MGRT"; RELATED_TRANSACTIONS = "J%5C%7B%3A";
          RELATED_TRANSACTIONS_AMOUNT = "m%3Evy";
        };
      };
      onepassword = {
        vault = "uq67q3orxxydw6yvrel3wvzpzy";
        service_account_token_ref = "op://Personal/Notion Finance Sync Service Account Token/password";
        bank_items = {
          bofa = "BofA"; bofa_investments = "BofA"; wells_fargo = "Wells Fargo";
          us_bank = "U.S. Bank"; everbank = "Everbank"; venmo = "Venmo";
          etrade = "4w52rrhmv7cc32hivgk3v5tecy"; fidelity = "Fidelity";
        };
      };
    };
  };
}
