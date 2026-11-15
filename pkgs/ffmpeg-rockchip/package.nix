{
  lib,
  fetchFromGitHub,
  ffmpeg-full,
  rockchip-mpp,
}:

let
  ffmpegRockchipBase = ffmpeg-full.override {
    version = "9.0.2";
    source = fetchFromGitHub {
      owner = "nyanmisaka";
      repo = "ffmpeg-rockchip";
      rev = "e6fd228e1e2be00f9a4e1f003b287a72d252a55d";
      hash = "sha256-OBoRfCtqISiFfIFYVsICHqmyaVnvf00MMTbeE5alnSE=";
    };

    # Keep the first integration build small and focused on playback/decode.
    withFullDeps = false;
    withHeadlessDeps = true;
    withSmallDeps = false;
    withCuda = false;
    withCudaLLVM = false;
    withCuvid = false;
    withNvcodec = false;
    withNvdec = false;
    withNvenc = false;
    withVulkan = false;
    withVaapi = false;
    withVdpau = false;
    withSdl2 = false;
    withVpx = true;
  };
in
ffmpegRockchipBase.overrideAttrs (old: {
  pname = "ffmpeg-rockchip";
  patches = [ ];
  buildInputs = old.buildInputs ++ [ rockchip-mpp ];
  configureFlags =
    (lib.filter (
      flag:
      !(builtins.elem flag [
        "--disable-libcelt"
        "--disable-libshaderc"
      ])
    ) old.configureFlags)
    ++ [ "--enable-rkmpp" ];

  meta = old.meta // {
    description = "FFmpeg with Rockchip MPP hardware codecs";
    homepage = "https://github.com/nyanmisaka/ffmpeg-rockchip";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
  };
})
