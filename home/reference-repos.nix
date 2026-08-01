{ config, lib, ... }:

# Reference repos (read-only clones under ~/Desktop/coding/reference-repos)
# declared here so a fresh machine reproduces the set. Activation clones any
# that are missing; it never updates or deletes — they're reference snapshots,
# refresh manually with git pull when needed.
# (The local `mail/` dir there has no remote — local-only, not declared.)
let
  root = "${config.home.homeDirectory}/Desktop/coding/reference-repos";
  repos = {
    "changedetection.io" = "https://github.com/dgtlmoon/changedetection.io";
    "cherrilang.org" = "https://github.com/electrikmilk/cherrilang.org.git";
    "google-api-nodejs-client" = "https://github.com/googleapis/google-api-nodejs-client";
    "heroicons" = "https://github.com/tailwindlabs/heroicons";
    "just" = "https://github.com/casey/just";
    "metasploit-framework" = "https://github.com/rapid7/metasploit-framework";
    "nixos-anywhere" = "https://github.com/nix-community/nixos-anywhere";
    "nixos-infect" = "https://github.com/elitak/nixos-infect";
    "nixpkgs" = "https://github.com/NixOS/nixpkgs";
    "oci-cli" = "https://github.com/oracle/oci-cli.git";
    "openclaw" = "https://github.com/openclaw/openclaw.git";
    "OpenSpec" = "https://github.com/Fission-AI/OpenSpec";
    "postiz-docs" = "https://github.com/gitroomhq/postiz-docs.git";
    "python-genai" = "https://github.com/googleapis/python-genai";
    "shell-plugins" = "https://github.com/1Password/shell-plugins.git";
    "spec-kit" = "https://github.com/github/spec-kit";
    "umami" = "https://github.com/umami-software/umami";
  };
in
{
  home.activation.referenceRepos = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "${root}"
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: url: ''
      [ -d "${root}/${name}" ] || /usr/bin/git clone --quiet "${url}" "${root}/${name}" || true
    '') repos)}
  '';
}
