# yabai — run from a stably-signed copy at a fixed path so its Accessibility
# grant survives updates.
#
# TCC keys Accessibility on the binary's PATH plus its designated requirement.
# nixpkgs' yabai is ad-hoc (linker-signed), so its DR is its cdhash and its
# path carries a store hash: every version bump — or any dependency rebuild of
# the same version — produced a new client macOS had never seen, killed the
# grant, and left the KeepAlive agent respawning yabai into an endless
# "yabai would like to control this computer" prompt loop.
#
# So activation copies the store binary to a fixed path and re-signs it with a
# stable self-signed cert (same trick as ScreenTimeBackup.app / StickerSync.app):
# path and code identity both hold across rebuilds, so the ONE manual grant on
# ${installPath} (MANUAL-macbook-air.md) is permanent.
#
# The scripting addition stays OFF: macOS 26.1's AMFI enforces library
# validation on Dock and refuses yabai's third-party ad-hoc payload, so SA-only
# features (space create/destroy, cross-display space moves, opacity, sticky
# windows) can't work regardless of SIP state. Hence no yabai-sa daemon and no
# /etc/sudoers.d/yabai.
{
  pkgs,
  username,
  ...
}:

let
  signingIdentity = "yabai-signing";
  installDir = "/Library/Application Support/yabai";
  installPath = "${installDir}/yabai";

  # `float` is yabai's own default (no auto-tiling); switch to "bsp" for
  # automatic tiling. A config file exists at all only so yabai stops warning
  # "could not locate config file" on every start.
  yabairc = pkgs.writeScript "yabairc" ''
    #!${pkgs.bash}/bin/bash
    ${pkgs.yabai}/bin/yabai -m config layout float
  '';
in
{
  system.activationScripts.postActivation.text = ''
    # Stable self-signed signing cert (one-time, idempotent).
    if ! /usr/bin/security find-certificate -c ${signingIdentity} /Library/Keychains/System.keychain >/dev/null 2>&1; then
      echo "creating code-signing identity ${signingIdentity} (one-time)..."
      _t="$(/usr/bin/mktemp -d)"
      /usr/bin/printf '[req]\ndistinguished_name=dn\nx509_extensions=v3\nprompt=no\n[dn]\nCN=%s\n[v3]\nbasicConstraints=critical,CA:false\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\n' ${signingIdentity} > "$_t/req.cnf"
      /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout "$_t/key.pem" -out "$_t/cert.pem" -config "$_t/req.cnf"
      # non-empty p12 password: `security` rejects empty-password PKCS12
      /usr/bin/openssl pkcs12 -export -inkey "$_t/key.pem" -in "$_t/cert.pem" -out "$_t/id.p12" -passout pass:yabai-signing-p12
      /usr/bin/security import "$_t/id.p12" -k /Library/Keychains/System.keychain -P yabai-signing-p12 -T /usr/bin/codesign -A
      /bin/rm -rf "$_t"
    fi

    # Re-install + re-sign every switch (rm first: the running binary can't be
    # overwritten in place, but unlinking it is fine).
    /bin/mkdir -p "${installDir}"
    /bin/rm -f "${installPath}"
    /bin/cp ${pkgs.yabai}/bin/yabai "${installPath}"
    /bin/chmod 0755 "${installPath}"
    /usr/bin/codesign --force --identifier yabai --sign ${signingIdentity} "${installPath}"

    # The agent's plist doesn't change on a yabai bump (the path is fixed), so
    # launchd won't reload it on its own — restart it to pick up the new binary.
    /bin/launchctl kickstart -k gui/"$(/usr/bin/id -u ${username})"/org.nixos.yabai 2>/dev/null || true
  '';

  launchd.user.agents.yabai = {
    serviceConfig = {
      ProgramArguments = [
        installPath
        "-c"
        "${yabairc}"
      ];
      KeepAlive = true;
      RunAtLoad = true;
      StandardOutPath = "/Users/${username}/Library/Logs/yabai.log";
      StandardErrorPath = "/Users/${username}/Library/Logs/yabai.log";
      ProcessType = "Interactive";
    };
  };

  # The `yabai` CLI (for `yabai -m ...` from a shell) stays the store build; it
  # only talks to the running server over its socket, so it needs no grant.
  environment.systemPackages = [ pkgs.yabai ];
}
