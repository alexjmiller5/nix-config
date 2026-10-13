{
  lib,
  stdenv,
  fetchurl,
  nodejs_24,
  importNpmLock,
  makeWrapper,
}:
let
  version = "6.4.0";
  lock = lib.importJSON (fetchurl {
    url = "https://raw.githubusercontent.com/morluto/rea/rea-agents-${version}/package-lock.json";
    hash = "sha256-tlXiEYl71yAy72kmG+hxDlA3se3neBBsj+9zAwetAFk=";
  });
  package = builtins.removeAttrs lock.packages."" [ "devDependencies" ];
  packageLock = lock // {
    packages = (lib.filterAttrs (_: value: !(value.dev or false)) lock.packages) // {
      "" = package;
    };
  };
in
stdenv.mkDerivation {
  pname = "rea-agents";
  inherit version;
  src = fetchurl {
    url = "https://registry.npmjs.org/rea-agents/-/rea-agents-${version}.tgz";
    hash = "sha256-WesWBLjbdfUi1Kl1w2zmtKKtRl5DutFl+aj3KDkdubg=";
  };
  npmDeps = importNpmLock { inherit package packageLock; };
  npmRebuildFlags = [ "--ignore-scripts" ];
  nativeBuildInputs = [
    nodejs_24
    importNpmLock.npmConfigHook
    makeWrapper
  ];
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/rea" "$out/bin"
    cp -R . "$out/lib/rea/"
    makeWrapper ${lib.getExe nodejs_24} "$out/bin/rea" \
      --add-flags "$out/lib/rea/scripts/rea.mjs"
    runHook postInstall
  '';
  meta = {
    description = "Evidence-driven reverse engineering tools and MCP server";
    homepage = "https://github.com/morluto/rea";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    mainProgram = "rea";
  };
}
