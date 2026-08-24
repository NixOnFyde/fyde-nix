{
  lib,
  stdenv,
  fetchFromGitHub,
  autoreconfHook,
}:
stdenv.mkDerivation {
  pname = "brcm-patchram-plus";
  version = "0.2-unstable-2026-04-01";

  src = fetchFromGitHub {
    owner = "NixOnFyde";
    repo = "brcm-patchram-plus";
    rev = "8b4a2d841b15ab312a99cccbe465f9c4fc3af5f4";
    hash = "sha256-jTlpX8Cw+7Ohn3haEgwGA6a+E5Y6hILGSig0yuEAVoQ=";
  };

  nativeBuildInputs = [ autoreconfHook ];

  meta = with lib; {
    description = "Broadcom Bluetooth firmware loader for UART-attached controllers";
    homepage = "https://github.com/NixOnFyde/brcm-patchram-plus";
    license = licenses.gpl2Plus;
    platforms = platforms.linux;
    mainProgram = "brcm_patchram_plus";
  };
}
