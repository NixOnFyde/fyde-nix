{
  stdenvNoCC,
  fetchurl,
  lib,
}:
stdenvNoCC.mkDerivation {
  pname = "himax-firmware";
  version = "2023-06-20";

  src = fetchurl {
    url = "https://raw.githubusercontent.com/NixOnFyde/overlay-fydetab_duo-openfyde/main/chromeos-base/chromeos-bsp-fydetab_duo-openfyde/files/firmware/Himax_firmware.bin";
    hash = "sha256-z0p/zXcNTBdhKCV6GmM2C8C02lu4Wkb2HP+Ir/nQJTc=";
  };

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm644 $src $out/lib/firmware/Himax_firmware.bin
    runHook postInstall
  '';

  meta = with lib; {
    description = "Himax HX83102 touchscreen firmware for the FydeTab Duo";
    license = licenses.unfreeRedistributable;
    platforms = platforms.all;
  };
}
