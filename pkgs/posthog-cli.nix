{
  lib,
  stdenvNoCC,
  fetchurl,
  fetchzip,
  makeWrapper,
  nodejs,
}:
let
  version = "0.18.1";
  sources = {
    aarch64-darwin = {
      target = "aarch64-apple-darwin";
      hash = "sha256-hNFhMApMiqzQ9kRSmUgfSLC+JcjCR7jN8pU4R5jZoC4=";
    };
    x86_64-darwin = {
      target = "x86_64-apple-darwin";
      hash = "sha256-du2SHdkLHgX64aXQCu9YcQ6Ff9QjGH5VtaZvIul/Gf4=";
    };
  };
  source = sources.${stdenvNoCC.hostPlatform.system};
in
stdenvNoCC.mkDerivation {
  pname = "posthog-cli";
  inherit version;
  src = fetchurl {
    url = "https://github.com/PostHog/posthog/releases/download/posthog-cli/v${version}/posthog-cli-${source.target}.tar.gz";
    inherit (source) hash;
  };
  nativeBuildInputs = [ makeWrapper ];
  dontStrip = true;
  installPhase = ''
    runHook preInstall
    install -Dm755 posthog-cli $out/libexec/posthog-cli
    install -Dm644 lib/posthog-api-cli.mjs $out/lib/posthog-api-cli.mjs
    makeWrapper $out/libexec/posthog-cli $out/bin/posthog-cli \
      --prefix PATH : ${lib.makeBinPath [ nodejs ]} \
      --set POSTHOG_API_CLI_PATH $out/lib/posthog-api-cli.mjs
    runHook postInstall
  '';
  # Reference material only: no MCP registration or session-upload hooks.
  passthru.skills = fetchzip {
    url = "https://github.com/PostHog/ai-plugin/archive/33c066c80776a962a4233d76b20a3317733070b4.tar.gz";
    hash = "sha256-/9yAPMMlpukyWMfIvU4f5lhaigL26y0a2nI10kSKnzo=";
  };
  meta = {
    description = "Official PostHog CLI with its agent API bundle";
    homepage = "https://posthog.com/docs/cli";
    license = lib.licenses.mit;
    platforms = builtins.attrNames sources;
    mainProgram = "posthog-cli";
  };
}
