{
  lib,
  glibc,
  stdenv,
  python3,
  dejavu_fonts,
  fydetabduo-plymouth-theme,
  wordmark ? ../fydetabduo-plymouth-theme/theme/fydetab-wordmark-hires.png,
}:

stdenv.mkDerivation {
  pname = "fydetab-boot-menu-ui";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [
    (python3.withPackages (ps: [ ps.pillow ]))
  ];

  buildInputs = [ glibc.static ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    python3 assets.py \
      --theme ${fydetabduo-plymouth-theme}/share/plymouth/themes/nixonfyde \
      --fonts ${dejavu_fonts}/share/fonts/truetype \
      --wordmark ${wordmark} \
      --out assets

    cc -O2 -Wall -Wextra -static -o fydetab-boot-menu-ui ui.c -lm

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 fydetab-boot-menu-ui $out/bin/fydetab-boot-menu-ui
    install -Dm644 assets/* -t $out/share/fydetab-boot-menu-ui

    runHook postInstall
  '';

  meta = {
    description = "Framebuffer generation picker for the FydeTab Duo initrd";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    maintainers = [ lib.maintainers.skifli ];
  };
}
