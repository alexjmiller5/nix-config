{
  config,
  lib,
  pkgs,
  ...
}:

{
  options.programs.rust-development.enable = lib.mkEnableOption "the Rust development toolchain";

  config = lib.mkIf config.programs.rust-development.enable {
    home.packages = with pkgs; [
      rustc
      cargo
      rustfmt
      clippy
      rust-analyzer
      cargo-nextest
      cargo-audit
    ];
    # Nix owns the compiler and standard-library sources, including for LSP.
    home.sessionVariables.RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";
  };
}
