{
  lib,
  pkgs,
  ...
}:
{
  hardware.graphics.enable = lib.mkDefault true;
  hardware.graphics.extraPackages = [ pkgs.rockchip-vaapi ];

  environment.sessionVariables.LIBVA_DRIVER_NAME = "rockchip";

  services.udev.extraRules = ''
    SUBSYSTEM=="mpp_class", KERNEL=="mpp_service", GROUP="video", MODE="0660"
  '';
}
