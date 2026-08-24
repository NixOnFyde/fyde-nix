{
  lib,
  stdenvNoCC,
  replaceVars,
  runCommand,
  coreutils,
  util-linux,
  parted,
  gptfdisk,
  dosfstools,
  btrfs-progs,
  rsync,
  idblock,
  uboot,
  resource,
}: let
  binPath = lib.makeBinPath [
    coreutils
    util-linux
    parted
    gptfdisk
    dosfstools
    btrfs-progs
    rsync
  ];

  scriptSrc = runCommand "fydetab-install-to-emmc.sh" {} ''
    cp ${./fydetab-install-to-emmc.sh} $out
  '';
in
  stdenvNoCC.mkDerivation {
    pname = "fydetab-install-to-emmc";
    version = "1.0.0";

    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;

    src = replaceVars scriptSrc {
      inherit idblock uboot resource;
      path = binPath;
    };

    installPhase = ''
      runHook preInstall
      install -Dm755 $src $out/bin/fydetab-install-to-emmc
      patchShebangs --host $out/bin/fydetab-install-to-emmc
      runHook postInstall
    '';

    meta = with lib; {
      description = "Clone the running FydeTab Duo system to internal eMMC";
      license = licenses.mit;
      platforms = platforms.linux;
      mainProgram = "fydetab-install-to-emmc";
    };
  }
