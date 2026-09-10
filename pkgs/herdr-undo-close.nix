{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  python3,
  herdr,
}:

stdenvNoCC.mkDerivation {
  pname = "herdr-undo-close";
  version = "0.3.0";
  src = fetchFromGitHub {
    owner = "pedroloch";
    repo = "herdr-undo-close";
    rev = "0c44b901717917ade80ae2ce0e921aeeabd67381";
    hash = "sha256-ouidTRf3h7l6UqvNJQa8VI0yJU448fiihbSnpRmGWYE=";
  };
  patches = [ ./herdr-undo-close.patch ];
  nativeCheckInputs = [
    python3
    herdr
  ];
  doCheck = true;
  checkPhase = ''
    PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests
    PYTHONDONTWRITEBYTECODE=1 python3 ${../tests/herdr-agent-restore.py} "$PWD"
  '';
  installPhase = ''
    mkdir -p $out
    cp -r herdr-plugin.toml herdr_undo_close $out/
  '';
  meta.license = lib.licenses.mit;
}
