{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [ ../modules/manual-steps.nix ];

  options.programs.go-development.enable = lib.mkEnableOption "the Go development toolchain";

  config = lib.mkIf config.programs.go-development.enable {
    home.packages = with pkgs; [
      go
      gopls
      gotools
      govulncheck
      delve
    ];
    # Toolchain versions are pinned by Nix, including when go.mod asks for newer Go.
    home.sessionVariables.GOTOOLCHAIN = lib.mkDefault "local";

    manual.steps = lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
      go-debugger-authorization = {
        title = "Go debugger authorization";
        owner = "go-development";
        desktop = true;
        body = ''
          The Go compiler, tests and race detector work without this step.
          For native Delve debugging, open a desktop Terminal (Screen Sharing
          on a headless host), run `sudo /usr/sbin/DevToolsSecurity -enable`,
          and approve the native debugger authorization when prompted.
          Verify with a local Go program built using
          `go build -gcflags='all=-N -l'` and `dlv exec <binary>`.
          Developer Mode status alone does not prove launch/attach works.
          Repeat native debugger authorization on a replacement machine.
        '';
        verify = null;
        redo = "after replacing the machine or when debugger launch/attach authorization fails";
      };
    };
  };
}
