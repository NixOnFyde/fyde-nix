{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hardware.fydetabduo.plymouth;
  plymouthFonts = pkgs.runCommand "fydetabduo-plymouth-fonts" { } ''
    mkdir -p $out
    cp ${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSansMono*.ttf $out/
  '';
  plymouthFontConfig = pkgs.writeText "fydetabduo-plymouth-fonts.conf" ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
    <fontconfig>
      <!-- Keep this path valid after Plymouth survives the initrd switchroot. -->
      <dir>${plymouthFonts}</dir>
      <cachedir>/tmp</cachedir>
      <alias binding="strong">
        <family>monospace</family>
        <prefer>
          <family>DejaVu Sans Mono</family>
        </prefer>
      </alias>
    </fontconfig>
  '';
in
{
  options.hardware.fydetabduo.plymouth.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Show a Plymouth boot splash on the internal DSI panel.

      ttyFIQ0 is always a serial console, so Plymouth is told to ignore
      serial consoles. Without that it stays in text mode and the boot
      can appear to hang.
    '';
  };

  config = lib.mkIf cfg.enable {
    # Plymouth's host-side console viewer uses the system fontconfig after the
    # initrd switches root, so keep its configured monospace family available.
    fonts.packages = [ pkgs.dejavu_fonts ];

    # Give Linux virtual consoles a Unicode font when the console is available.
    # Plymouth's script-rendered text selects DejaVu Sans Mono in the theme;
    # systemd can skip vconsole setup while Plymouth owns the only allocated VT.
    console = {
      earlySetup = lib.mkDefault true;
      font = lib.mkDefault "ter-u16n";
      packages = [ pkgs.terminus_font ];
    };

    boot.plymouth = {
      enable = lib.mkDefault true;
      # bgrt needs an ACPI BGRT image, which this device-tree platform
      # does not provide.
      theme = lib.mkDefault "nixonfyde";
      themePackages = [ pkgs.fydetabduo-plymouth-theme ];
      font = lib.mkDefault "${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSansMono.ttf";
    };

    # The Plymouth console viewer needs the bold face as well as the regular
    # face to render bold kernel and systemd messages correctly. NixOS's
    # boot.plymouth.font option copies only one file into the systemd initrd.
    boot.initrd.systemd.contents."/etc/plymouth/fonts".source = lib.mkForce plymouthFonts;
    # The generated initrd fontconfig file only lists the font directory and
    # lacks the generic aliases used by Plymouth's console viewer.
    boot.initrd.systemd.contents."/etc/fonts/fonts.conf".source = lib.mkForce plymouthFontConfig;

    # Plymouth's FreeType label plugin uses Nixpkgs' absolute fc-match path.
    # libfontconfig alone is not enough if the initrd falls back to that plugin.
    boot.initrd.systemd.storePaths = [ pkgs.fontconfig.bin ];

    # This panel's 1600x2560 mode and 166x266 mm size make Plymouth choose 2x.
    # The script theme uses 1x coordinates, so render it at scale 1 and prepare
    # its assets at 2x instead of letting Plymouth interpolate every image, cus
    # tha blurry af.
    boot.initrd.systemd.services.plymouth-start.environment = {
      FONTCONFIG_FILE = "/etc/fonts/fonts.conf";
      PLYMOUTH_FORCE_SCALE = "1";
    };

    # Shutdown/reboot Plymouth starts a new host-side daemon after the
    # initrd daemon exits. Keep those modes at the same scale as the boot art.
    systemd.services =
      lib.genAttrs
        [
          "plymouth-halt"
          "plymouth-poweroff"
          "plymouth-reboot"
          "plymouth-kexec"
        ]
        (_: {
          environment.PLYMOUTH_FORCE_SCALE = "1";
        });

    boot.kernelParams = lib.optionals config.boot.plymouth.enable [
      "plymouth.ignore-serial-consoles"
    ];
  };
}
