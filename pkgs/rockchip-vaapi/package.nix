{
  lib,
  stdenv,
  fetchFromGitHub,
  pkg-config,
  libva,
  rockchip-mpp,
}:

stdenv.mkDerivation {
  pname = "rockchip-vaapi";
  version = "1.0.12";

  src = fetchFromGitHub {
    owner = "woodyst";
    repo = "rockchip-vaapi";
    rev = "08559e8a00e81b6bc8713943485310a88fd2b2b2";
    hash = "sha256-qA5vDWuQXeYM2fGwZnFbHDePKjwsQOStsnArkB86sj8=";
  };

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [
    libva
    rockchip-mpp
  ];

  buildPhase = ''
    runHook preBuild
    make \
      CC=${stdenv.cc}/bin/cc \
      CFLAGS="-O2 -Wall -Wextra -fPIC -shared $(pkg-config --cflags libva rockchip_mpp)" \
      LDFLAGS="$(pkg-config --libs libva rockchip_mpp) -lpthread -ldl"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 rockchip_drv_video.so "$out/lib/dri/rockchip_drv_video.so"
    install -Dm644 LICENSE "$out/share/licenses/rockchip-vaapi/LICENSE"
    runHook postInstall
  '';

  meta = {
    description = "VA-API driver connecting Rockchip MPP to VA-API clients";
    homepage = "https://github.com/woodyst/rockchip-vaapi";
    license = lib.licenses.lgpl21Plus;
    platforms = lib.platforms.linux;
  };
}
