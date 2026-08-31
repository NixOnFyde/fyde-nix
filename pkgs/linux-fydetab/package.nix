{
  lib,
  fetchFromGitHub,
  linuxKernel,
  features ? { },
  kernelPatches ? [ ],
  randstructSeed ? "",
}:
let
  fydetabPatches = [
    {
      name = "selinux-drop-duplicate-DONTAUDIT-definition";
      patch = ./0001-selinux-drop-duplicate-DONTAUDIT-definition.patch;
    }
    {
      name = "rknpu-add-npu-driver";
      patch = ./0002-rknpu-add-npu-driver.patch;
    }
    {
      name = "rknpu-fix-build-for-6.12";
      patch = ./0003-rknpu-fix-build-for-6.12.patch;
    }
  ];

  allKernelPatches = fydetabPatches ++ kernelPatches;
in
linuxKernel.buildLinux rec {
  inherit
    features
    randstructSeed
    ;

  kernelPatches = allKernelPatches;

  version = "6.12.43";
  modDirVersion = version;
  pname = "linux-fydetab";

  src = fetchFromGitHub {
    owner = "NixOnFyde";
    repo = "linux-fydetabduo";
    rev = "141bc9b36bc35738c4ea90f4c90d39d2e9cd5f0c";
    hash = "sha256-YnQT5FLv2PbaoYdVOElnUvIlIjOeXpN/htKQ2Gmc5u8=";
  };

  defconfig = "fydetabduo_defconfig";

  enableCommonConfig = false;

  structuredExtraConfig = with lib.kernel; {
    STATIC_USERMODEHELPER = no;

    SECURITY_LOADPIN = no;

    DPM_WATCHDOG = no;

    DRM_PANTHOR = module;

    FW_LOADER_COMPRESS = yes;
    FW_LOADER_COMPRESS_ZSTD = yes;

    MALI = no;

    ROCKCHIP_DW_HDCP2 = no;

    ROCKCHIP_DP_MST_AUX_CLIENT = no;

    ROCKCHIP_MMC_VENDOR_STORAGE = no;

    RD_GZIP = yes;
    RD_ZSTD = yes;

    FRAMEBUFFER_CONSOLE = yes;

    SECURITY_SELINUX = yes;
    SECURITY_SELINUX_BOOTPARAM = yes;
    SECURITY_SELINUX_DEVELOP = yes;
    SECURITY_SELINUX_PERMISSIVE_DONTAUDIT = yes;
    SECURITY_APPARMOR = yes;
    SECURITY_YAMA = yes;
    SECURITY_SAFESETID = yes;

    BTRFS_FS = module;

    NF_TABLES = module;
    NF_TABLES_INET = yes;
    NFT_COMPAT = module;
    NFT_LOG = module;
    NFT_LIMIT = module;
    NFT_CT = module;
    NFT_NAT = module;
    NFT_MASQ = module;
    NFT_REJECT = module;
    NETFILTER_XT_TARGET_LOG = module;
    NETFILTER_XT_MATCH_MULTIPORT = module;
    NETFILTER_XT_MATCH_RECENT = module;
    NETFILTER_XT_MATCH_HL = module;
    BRIDGE_NETFILTER = module;
    IP6_NF_MATCH_RT = module;

    ROCKCHIP_RKNPU = yes;
    ROCKCHIP_RKNPU_DRM_GEM = yes;
    ROCKCHIP_RKNPU_DEBUG_FS = yes;
  };

  extraMeta = {
    description = "Linux kernel for the FydeTab Duo (RK3588S tablet)";
    platforms = [ "aarch64-linux" ];
  };
}
