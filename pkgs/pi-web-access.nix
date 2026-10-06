{
  lib,
  stdenv,
  nodejs_22,
  importNpmLock,
  source,
}:
let
  # Pi supplies its own API modules. Install only this extension's runtime
  # dependencies, without its development copy of the entire Pi toolchain.
  package = builtins.removeAttrs (lib.importJSON (source + "/package.json")) [
    "devDependencies"
    "peerDependencies"
    "peerDependenciesMeta"
  ];
  lock = lib.importJSON (source + "/package-lock.json");
  packageLock = lock // {
    packages = (lib.filterAttrs (_: value: !(value.dev or false)) lock.packages) // {
      "" = package;
    };
  };
in
stdenv.mkDerivation {
  pname = "pi-web-access";
  version = (lib.importJSON (source + "/package.json")).version;
  src = source;
  npmDeps = importNpmLock { inherit package packageLock; };
  npmRebuildFlags = [ "--ignore-scripts" ];
  nativeBuildInputs = [
    nodejs_22
    importNpmLock.npmConfigHook
  ];
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -R . "$out/"
    runHook postInstall
  '';
  meta = {
    description = "Web search and content extraction extension for Pi";
    homepage = "https://github.com/nicobailon/pi-web-access";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
