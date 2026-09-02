{ pkgs, cherri, ... }:

# Portable dev toolbox shared by BOTH hosts — everything needed to clone,
# build, and deploy projects from either machine. Laptop-only tooling
# (Apple build chain, GUI helpers, fonts) stays in home/macbook-air.nix;
# op-authed CLI wrappers (gh, modal, gog, gcloud, wrangler) live in
# op-wrappers.nix.
# Exported via homeModules; consumers must pass `cherri` through
# extraSpecialArgs (like vscode.nix's input).
{
  home.packages = [
    pkgs.bun
    pkgs.exiftool
    pkgs.ffmpeg
    pkgs.oci-cli
    pkgs.pnpm
    pkgs.terraform # unfree (BSL) — allowed in each host's predicate
    pkgs.yt-dlp
    # Cherri compiler for the ios-shortcuts project (flake input; not in nixpkgs).
    cherri.packages.${pkgs.stdenv.hostPlatform.system}.default
    # memo (Apple Notes CLI, antoniorodr/memo) — needed by the apple-notes /
    # triage-apple-notes agent skills. Not in nixpkgs, and its brew formula's
    # python was broken, so run it uv-style: uvx resolves from git once and
    # reuses the cached env (refresh = `uvx --refresh --from … memo`).
    (pkgs.writeShellApplication {
      name = "memo";
      runtimeInputs = [ pkgs.uv ];
      text = ''
        exec uvx --from git+https://github.com/antoniorodr/memo memo "$@"
      '';
    })
  ];
}
