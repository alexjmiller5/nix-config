{
  config,
  lib,
  pkgs,
  pi,
  pi-calm,
  pi-web-access,
  pi-fast-mode,
  ...
}:
let
  cfg = config.programs.pi-coding-agent;
  agentConfig = "${config.xdg.configHome}/agent-config";
  link = config.lib.file.mkOutOfStoreSymlink;
  web = pkgs.callPackage ../pkgs/pi-web-access.nix { source = pi-web-access; };
in
{
  imports = [ ../modules/manual-steps.nix ];

  config = lib.mkMerge [
    {
      programs.pi-coding-agent = {
        enable = lib.mkDefault true;
        package = lib.mkDefault pi.packages.${pkgs.stdenv.hostPlatform.system}.default;
      };
    }
    (lib.mkIf cfg.enable {
      home.file = {
        "${cfg.configDir}/AGENTS.md".source = link "${agentConfig}/AGENTS.md";
        "${cfg.configDir}/skills".source = link "${agentConfig}/skills";
        # Pi persists model and extension preferences here. The companion repo
        # owns the writable configuration, as it does for the other agents.
        "${cfg.configDir}/settings.json".source = link "${agentConfig}/pi/settings.json";
        "${cfg.configDir}/mcp.json" =
          lib.mkIf (config.programs.mcp.enable && config.programs.mcp.servers != { })
            {
              source = config.xdg.configFile."mcp/mcp.json".source;
            };
        "${cfg.configDir}/extensions/agent-config.ts".source = link "${agentConfig}/pi/agent-config.ts";
        "${cfg.configDir}/extensions/calm".source = "${pi-calm}/home/.pi/agent/extensions/calm";
        "${cfg.configDir}/extensions/web-access".source = web;
        "${cfg.configDir}/extensions/codex-fast-mode.ts".source =
          "${pi-fast-mode}/packages/codex-fast-mode/index.ts";
        "${cfg.configDir}/themes/rose-pine-moon.json".source =
          "${pi-calm}/home/.pi/agent/themes/rose-pine-moon.json";
      };

      # Use the applications' own idempotent adapters. Neither changes titles.
      home.activation.piIntegrations = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        ${lib.optionalString config.programs.herdr.enable "run ${lib.getExe config.programs.herdr.package} integration install pi"}
        ${lib.optionalString pkgs.stdenv.hostPlatform.isDarwin ''
          export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
        ''}
        if command -v moshi-hook >/dev/null; then
          run moshi-hook install --target pi
        fi
      '';

      manual.steps.pi-login = {
        title = "Pi provider login";
        owner = "pi";
        desktop = false;
        body = ''
          Start `pi` in Herdr and run `/login`, then choose the provider and
          complete its browser authorization. Pi owns its credential store under
          `~/.pi/agent`; do not copy another agent's OAuth session. Repeat on each
          replacement machine. `/model` chooses the model after enrollment.

          `/calm` toggles tool-output visibility and persists the choice locally.
          `/codex-fast on` enables the optional priority tier for supported Codex models;
          it can consume quota faster. The theme is Rosé Pine Moon. Shared skills,
          MCP servers, Superpowers, Ponytail, Herdr and Moshi load automatically.
        '';
        verify = "pi auth check --provider openai-codex --json >/dev/null";
        redo = "on a replacement machine or after revoking the provider session";
      };
    })
  ];
}
