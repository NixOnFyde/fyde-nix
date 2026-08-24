{
  lib,
  stdenvNoCC,
}:
stdenvNoCC.mkDerivation {
  name = "fydetab-wallpaper";

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm644 ${./wallpaper.jpg} \
      $out/share/backgrounds/fydetab-duo/wallpaper.jpg
    runHook postInstall
  '';

  meta = {
    description = "Default wallpaper for the FydeTab Duo image";
    platforms = lib.platforms.linux;
  };
}
