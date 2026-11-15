{ ... }:
{
  services.udev.extraRules = ''
    SUBSYSTEM=="mpp_class", KERNEL=="mpp_service", GROUP="video", MODE="0660"
  '';
}
