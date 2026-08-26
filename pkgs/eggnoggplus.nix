# EGGNOGG+ (madgarden.itch.io/eggnogg) — itch.io-only, served via signed
# expiring URLs, so no cask/plain-fetchurl is possible. The fixed-output src
# derivation replays itch's anonymous download dance (csrf → POST → signed
# URL) at fetch time; the pinned hash keeps it reproducible. Build unchanged
# since 2015 (upload 138870); x86_64-only, needs Rosetta (installed by
# hosts/macbook-air.nix postActivation). Lands in
# ~/Applications/Home Manager Apps.
{
  stdenvNoCC,
  curl,
  cacert,
  unzip,
}:
let
  zip = stdenvNoCC.mkDerivation {
    name = "eggnoggplus-osx.zip";
    nativeBuildInputs = [
      curl
      cacert
    ];
    SSL_CERT_FILE = "${cacert}/etc/ssl/certs/ca-bundle.crt";
    buildCommand = ''
      csrf=$(curl -s -c cookies.txt https://madgarden.itch.io/eggnogg \
        | grep -oE 'csrf_token" value="[^"]+' | cut -d'"' -f3)
      url=$(curl -s -b cookies.txt -X POST \
        "https://madgarden.itch.io/eggnogg/file/138870?source=game_download" \
        --data-urlencode "csrf_token=$csrf" \
        | grep -oE '"url":"[^"]+' | cut -d'"' -f4 | sed 's|\\/|/|g')
      curl -sL "$url" -o "$out"
    '';
    outputHashAlgo = "sha256";
    outputHashMode = "flat";
    outputHash = "sha256-u3/eKr4/jG44DUV9UMK5kcfm/98Fnhh2obt/Wwl341U=";
  };
in
stdenvNoCC.mkDerivation {
  pname = "eggnoggplus";
  version = "1.0";
  src = zip;
  nativeBuildInputs = [ unzip ];
  unpackPhase = "unzip -q $src";
  installPhase = ''
    mkdir -p $out/Applications
    cp -R eggnoggplus.app $out/Applications/
  '';
}
