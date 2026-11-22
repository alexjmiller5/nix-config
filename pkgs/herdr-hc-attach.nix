{ lib, stdenvNoCC, fetchFromGitHub, nodejs }:
stdenvNoCC.mkDerivation {
  pname = "herdr-hc-attach";
  version = "0.1.0";
  src = fetchFromGitHub {
    owner = "barnuri";
    repo = "herdr-hc-attach";
    rev = "cb7b6ed2ac8ed7e8a36b801507a3c0eaaaa15ff8";
    sha256 = "1hclfzvpspvf3cqvn1a4nbm77bfxy86spvsw63d69h1l08fgaz9p";
  };
  patches = [ ./herdr-hc-attach.patch ];
  nativeCheckInputs = [ nodejs ];
  doCheck = true;
  checkPhase = "node --test tests/*.test.js";
  installPhase = ''
    mkdir -p $out
    cp -r bin lib scripts herdr-plugin.toml $out/
    chmod +x $out/bin/hc-shell $out/scripts/ensure-sync.sh
  '';
  meta = {
    description = "Original Herdr TUI views of existing Core terminals";
    license = lib.licenses.mit;
  };
}
