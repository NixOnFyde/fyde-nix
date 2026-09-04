final: _prev: {
  linuxPackages_fydetab = final.linuxPackagesFor (
    final.callPackage ../pkgs/linux-fydetab/package.nix { kernelPatches = [ ]; }
  );
  linux_fydetab = final.linuxPackages_fydetab.kernel;

  ap6275p-firmware = final.callPackage ../pkgs/ap6275p-firmware/package.nix { };
  himax-firmware = final.callPackage ../pkgs/himax-firmware/package.nix { };
  librknnrt = final.callPackage ../pkgs/librknnrt/package.nix { };
  brcm-patchram-plus = final.callPackage ../pkgs/brcm-patchram-plus/package.nix { };
  rk-boot-script = final.callPackage ../pkgs/rk-boot-script/package.nix { };

  fydetab-blob-idblock = final.runCommand "fydetab-idblock.bin" { } ''
    cp ${../blobs/bootchain/idblock.bin} $out
  '';
  fydetab-blob-uboot = final.runCommand "fydetab-uboot.img" { } ''
    cp ${../blobs/bootchain/uboot.img} $out
  '';
  fydetab-blob-resource = final.runCommand "fydetab-resource.img" { } ''
    cp ${../blobs/bootchain/resource.img} $out
  '';

  fydetab-install-to-emmc = final.callPackage ../pkgs/fydetab-install-to-emmc/package.nix {
    idblock = final.fydetab-blob-idblock;
    uboot = final.fydetab-blob-uboot;
    resource = final.fydetab-blob-resource;
  };
  fydetab-snapshot = final.callPackage ../pkgs/fydetab-snapshot/package.nix { };
  fydetab-update = final.callPackage ../pkgs/fydetab-update/package.nix { };
  fydetab-wallpaper = final.callPackage ../pkgs/fydetab-wallpaper/package.nix { };
  fydetab-update-bootchain = final.callPackage ../pkgs/fydetab-update-bootchain/package.nix {
    idblock = final.fydetab-blob-idblock;
    uboot = final.fydetab-blob-uboot;
    resource = final.fydetab-blob-resource;
  };

  ghostty-zink = final.callPackage ../pkgs/ghostty-zink/package.nix { };
}
