{
  lib,
  stdenvNoCC,
  bash,
  coreutils,
  util-linux,
  gnused,
  gawk,
  btrfs-progs,
  replaceVars,
}:
let
  binPath = lib.makeBinPath [
    coreutils
    util-linux
    gnused
    gawk
    btrfs-progs
  ];
in
stdenvNoCC.mkDerivation {
  pname = "fydetab-snapshot";
  version = "1.0.0";

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 ${
      replaceVars ./fydetab-snapshot.sh {
        inherit bash;
        path = binPath;
      }
    } $out/bin/fydetab-snapshot

    runHook postInstall
  '';

  meta = with lib; {
    description = "Create and roll back btrfs system snapshots";
    platforms = lib.platforms.linux;
  };
}
