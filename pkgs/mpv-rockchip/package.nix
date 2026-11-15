{ mpv, mpv-unwrapped, ffmpeg-rockchip }:

mpv.override {
  mpv-unwrapped = mpv-unwrapped.override {
    ffmpeg = ffmpeg-rockchip;
  };
}
