{
  lib,
  stdenv,
}:
stdenv.mkDerivation {
  pname = "fydetab-wake-activity";
  version = "1.0.0";

  src = ./.;

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    $CC -O2 -Wall -o fydetab-wake-activity fydetab-wake-activity.c
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 fydetab-wake-activity $out/bin/fydetab-wake-activity
    runHook postInstall
  '';

  meta = with lib; {
    description = "Inject a synthetic key event via uinput after a power-key wake so compositors do register user activity";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "fydetab-wake-activity";
  };
}
