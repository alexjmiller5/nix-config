{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule {
  pname = "herdr-auto-title";
  version = "0.5.0";
  src = fetchFromGitHub {
    owner = "kryptamine";
    repo = "herdr-auto-title";
    rev = "d951862d7c78f24957673dc106572e0ed94e4068";
    hash = "sha256-IophxKOw4kbYApUu61paYrX1wYcocvaKqb/zEbNeycw=";
  };
  vendorHash = "sha256-QxFp1b7pf7bn3Hh0hyaj8ke5Z61N+WwjhHt3pFiapTs=";
  subPackages = [ "cmd/herdr-auto-title" ];
  checkPhase = ''
    runHook preCheck
    go test -race ./...
    runHook postCheck
  '';
  postInstall = ''
    cp herdr-plugin.toml $out/
    substituteInPlace $out/herdr-plugin.toml \
      --replace-fail '"./herdr-auto-title"' '"${placeholder "out"}/bin/herdr-auto-title"'
    # Start through Herdr's process runner when installing into a live session.
    cat >> $out/herdr-plugin.toml <<'EOF'

    [[actions]]
    id = "start"
    title = "Start automatic tab titles"
    command = ["${placeholder "out"}/bin/herdr-auto-title"]
    EOF
  '';
  meta = {
    description = "Automatic contextual tab titles for Herdr";
    homepage = "https://github.com/kryptamine/herdr-auto-title";
    license = lib.licenses.mit;
    mainProgram = "herdr-auto-title";
  };
}
