{
  lib,
  stdenv,
  python3,
}:
stdenv.mkDerivation {
  pname = "rk-boot-script";
  version = "1.0.0";

  src = ./.;

  dontConfigure = true;
  dontBuild = true;

  nativeBuildInputs = [python3];

  installPhase = ''
    runHook preInstall
    install -Dm755 rk-mkimage.py $out/bin/rk-mkimage
    patchShebangs $out/bin/rk-mkimage
    runHook postInstall
  '';

  meta = with lib; {
    description = "Compile U-Boot scripts for Rockchip vendor bootloaders (legacy uImage, 0xffffffff terminator)";
    license = licenses.mit;
    platforms = platforms.all;
    mainProgram = "rk-mkimage";
  };
}
