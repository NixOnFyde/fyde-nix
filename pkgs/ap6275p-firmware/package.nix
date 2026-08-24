{
  lib,
  stdenvNoCC,
  fetchurl,
}:
let
  rev = "794da2662def953ddd64cd8ac14298571b797326";
  base = "https://raw.githubusercontent.com/NixOnFyde/firmware/${rev}/ap6275p";
in
stdenvNoCC.mkDerivation {
  pname = "ap6275p-firmware";
  version = "2024-08-04";

  srcs = [
    (fetchurl {
      url = "${base}/fw_bcm43752a2_pcie_ag.bin";
      hash = "sha256-ai2+AeciId77qRpS4Vh2jZc6PIXKLYgckkN541rTayM=";
    })
    (fetchurl {
      url = "${base}/nvram_AP6275P.txt";
      hash = "sha256-4iPaoA9xaml9CSffQNPLjjb3E7RdzfVgvOwSjGzY+HY=";
    })
    (fetchurl {
      url = "${base}/clm_bcm43752a2_pcie_ag.blob";
      hash = "sha256-2BuorcizvApViRRrMbwxgSJpPYoRalAo0/6CZVbFqSo=";
    })
    (fetchurl {
      url = "${base}/config.txt";
      hash = "sha256-ibe6wnIC5wCeAAaN1nQ2IRhfMI64XFMbGM86SaWlnzQ=";
    })
    (fetchurl {
      url = "${base}/BCM4362A2.hcd";
      hash = "sha256-GJAaW+8dQYtolektCvrjYjT0FgsjdGXfyj116YROk+8=";
    })
  ];

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/firmware/ap6275p

    for f in $srcs; do
      cp "$f" "$out/lib/firmware/ap6275p/$(stripHash "$f")"
    done

    ln -s nvram_AP6275P.txt $out/lib/firmware/ap6275p/nvram_ap6275p.txt
    runHook postInstall
  '';

  meta = with lib; {
    description = "Broadcom AP6275P (BCM43752) WiFi and Bluetooth firmware";
    license = licenses.unfreeRedistributable;
    platforms = platforms.all;
  };
}
