{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  pkg-config,
}:

stdenv.mkDerivation {
  pname = "rockchip-mpp";
  version = "1.3.10-unstable-2026-11-03";

  src = fetchFromGitHub {
    owner = "rockchip-linux";
    repo = "mpp";
    rev = "9b56348cc61393c84662e6d6dd78feae67773a36";
    hash = "sha256-uBi73uahwOQSnyxfaF66bMeoDb9yJfRawE29bqBeRzQ=";
  };

  nativeBuildInputs = [
    cmake
    pkg-config
  ];

  cmakeFlags = [
    "-DBUILD_TEST=OFF"
    "-DCMAKE_BUILD_TYPE=Release"
    "-DCMAKE_INSTALL_INCLUDEDIR=include"
    "-DCMAKE_INSTALL_LIBDIR=lib"
  ];

  meta = with lib; {
    description = "Rockchip Media Process Platform userspace library";
    homepage = "https://github.com/rockchip-linux/mpp";
    license = licenses.asl20;
    platforms = platforms.linux;
  };
}
