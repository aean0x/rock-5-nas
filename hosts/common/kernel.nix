# Kernel configuration for ROCK5 ITX
{ lib, pkgs, ... }:

# Kernel pinned to 6.18 for ZFS compatibility
let
  kernelOverride = pkgs.linux_6_18.override {
    extraConfig = ''
      ROCKCHIP_DW_HDMI_QP y
    '';
  };
in
{
  boot.kernelPackages = pkgs.linuxPackagesFor kernelOverride;
  powerManagement.cpuFreqGovernor = lib.mkDefault "performance";
  hardware.enableRedistributableFirmware = true;
  networking.useDHCP = lib.mkDefault true;
  hardware.deviceTree.enable = true;
  hardware.deviceTree.name = "rockchip/rk3588-rock-5-itx.dtb";
  hardware.deviceTree.filter = "*-rock-5-itx*.dtb";
  boot.loader.systemd-boot.extraFiles."dtb/rockchip/rk3588-rock-5-itx.dtb" =
    "${kernelOverride}/dtbs/rockchip/rk3588-rock-5-itx.dtb";

  boot = {
    kernelParams = [
      "rootwait"
      "rw" # load rootfs as read-write
      "earlycon" # enable early console, so we can see the boot messages via serial port / HDMI
      "consoleblank=0" # disable console blanking(screen saver)
      "console=tty0"
      "console=ttyAML0,115200n8"
      "console=ttyS0,1500000n8"
      "console=ttyS2,1500000n8"
      "console=ttyFIQ0,1500000n8"
      "coherent_pool=2M"
      "irqchip.gicv3_pseudo_nmi=0"
      # show boot logo
      "splash"
      "plymouth.ignore-serial-consoles"
      # docker optimizations
      "cgroup_enable=cpuset"
      "cgroup_memory=1"
      "cgroup_enable=memory"
      "swapaccount=1"
      # Device tree boot parameter per wiki
      # "dtb=/${config.hardware.deviceTree.name}"
      "rockchip.pmu=off" # Disable problematic power management features
      "pci=nomsi" # Disable MSI interrupts that can cause issues
      "ignore_loglevel" # Show more detailed boot messages
    ];

    initrd.availableKernelModules = [
      # NVMe
      "nvme"
      # SD cards and internal eMMC drives.
      "mmc_block"
      # Support USB keyboards
      "hid"
      # For LUKS encrypted root partition.
      "dm_mod" # for LVM & LUKS
      "dm_crypt" # for LUKS
      "input_leds"
    ];
  };
}
