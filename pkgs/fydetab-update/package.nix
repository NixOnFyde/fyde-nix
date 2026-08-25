{
  lib,
  stdenvNoCC,
  bash,
  coreutils,
  git,
  gnugrep,
  gnused,
  nix,
  nixos-rebuild,
  procps,
  sudo,
  replaceVars,
}:
let
  binPath = lib.makeBinPath [
    coreutils
    git
    gnugrep
    gnused
    nix
    nixos-rebuild
    procps
    sudo
  ];
in
stdenvNoCC.mkDerivation {
  pname = "fydetab-update";
  version = "1.0.0";

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 ${
      replaceVars ./fydetab-update.sh {
        inherit bash;
        path = binPath;
      }
    } $out/bin/fydetab-update

    runHook postInstall
  '';

  meta = with lib; {
    description = "Update the FydeTab Duo to the latest tagged fyde-nix release and rebuild";
    platforms = lib.platforms.linux;
  };
}
