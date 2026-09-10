{
  config,
  lib,
  ...
}:
let
  cfg = config.hardware.fydetabduo.fingerprint;
in
{
  options.hardware.fydetabduo.fingerprint = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Load the Microarray AFS120 fingerprint driver (microarray_fp) at
        boot and give the login user access to its /dev/madev0 device.

        The kernel driver is built into the tree but is never autoloaded:
        it only carries an `of:` modalias alias while the SPI core emits
        `spi:microarray-fp`, so udev cannot modprobe it. This module
        forces the load and exposes the device node.

        NOTE: there is no mainline libfprint driver for the AFS120 yet,
        so this only exposes the raw REE char device (/dev/madev0) and
        the input events it emits. A user-level libfprint driver for
        the vendor ioctl protocol is still required for enrollment /
        authentication using fprintd.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Force-load the SPI driver. This module has no spi: modalias alias
    # (only of:), so the SPI core's spi:microarray-fp modalias cannot
    # cause the udev autoload.
    boot.kernelModules = [ "microarray_fp" ];

    services.udev.extraRules = ''
      KERNEL=="madev0", MODE="0660", GROUP="wheel", TAG+="uaccess"
    '';
  };
}
