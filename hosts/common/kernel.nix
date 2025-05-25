# Kernel configuration for ROCK5 ITX
{ lib, pkgs, config, settings, ... }:

{
  powerManagement.cpuFreqGovernor = lib.mkDefault "performance";
  hardware.enableRedistributableFirmware = true;
  networking.useDHCP = lib.mkDefault true;
  hardware.deviceTree.enable = true;
  hardware.deviceTree.name = "rockchip/rk3588-rock-5-itx.dtb";
  hardware.deviceTree.filter = "*-rock-5-itx*.dtb";
  boot.loader.systemd-boot.extraFiles."dtb/rockchip/rk3588-rock-5-itx.dtb" = "${pkgs.linuxPackages_latest.kernel}/dtbs/rockchip/rk3588-rock-5-itx.dtb";

  boot = {
    kernelPackages = pkgs.linuxPackages_latest;

    kernelParams = [
      "rootwait"
      "earlycon" # enable early console, so we can see the boot messages via serial port / HDMI
      "consoleblank=0" # disable console blanking(screen saver)
      "console=ttyS2,1500000" # serial port
      "console=tty1" # HDMI
    ];

    initrd.kernelModules = [
      # Rockchip modules
      "rockchip_rga"
      "rockchip_saradc"
      "rockchip_thermal"
      "rockchipdrm"
      # GPU/Display modules
      "analogix_dp"
      "cec"
      "drm"
      "drm_kms_helper"
      "dw_hdmi"
      "dw_mipi_dsi"
      "gpu_sched"
      "panel_edp"
      "panel_simple"
      "panfrost"
      "pwm_bl"
      # USB / Type-C related modules
      "fusb302"
      "tcpm"
      "typec"
      "dwc3"
      "usb-storage"
      # Storage modules
      "ahci"
      # Misc. modules
      "cw2015_battery"
      "gpio_charger"
      "rtc_rk808"
    ];

    supportedFilesystems = lib.mkForce [
      "btrfs"
      "reiserfs"
      "vfat"
      "f2fs"
      "xfs"
      "ntfs"
      "cifs"
    ];
  };
}