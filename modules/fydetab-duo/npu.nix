{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.fydetabduo.npu;
in
{
  options.hardware.fydetabduo.npu = {
    enable = lib.mkEnableOption ''
      the RK3588S NPU using the vendor rknpu driver and librknnrt runtime.
      Provides /dev/dri/renderD129 and the RKNN C API for INT8/INT4/FP16
      inference on the three NPU cores.
    '';
  };

  config = lib.mkIf cfg.enable {
    boot.kernelModules = [ "rknpu" ];

    environment.systemPackages = [ pkgs.librknnrt ];

    environment.sessionVariables.LD_LIBRARY_PATH = [
      "${pkgs.librknnrt}/lib"
      "${pkgs.stdenv.cc.cc.lib}/lib"
    ];
  };
}
