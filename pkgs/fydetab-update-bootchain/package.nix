{
  lib,
  stdenvNoCC,
  bash,
  coreutils,
  util-linux,
  gawk,
  diffutils,
  replaceVars,
  runCommand,
  idblock,
  uboot,
  resource,
}:
let
  scriptSrc = runCommand "update-bootchain.sh" { } ''
    cp ${./update-bootchain.sh} $out
  '';
in
stdenvNoCC.mkDerivation {
  pname = "fydetab-update-bootchain";
  version = "1.0.0";

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 ${
      replaceVars scriptSrc {
        inherit
          bash
          idblock
          uboot
          resource
          ;
        path = lib.makeBinPath [
          coreutils
          util-linux
          gawk
          diffutils
        ];
      }
    } $out/bin/fydetab-update-bootchain

    runHook postInstall
  '';

  meta = with lib; {
    description = "Rewrite FydeTab Duo boot ROM blobs in place";
    platforms = lib.platforms.linux;
  };
}
