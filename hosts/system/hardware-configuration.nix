{
  modulesPath,
  ...
}:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  # Default hardware settings that apply regardless of storage layout
  hardware.cpu.arm.enable = true;
  hardware.enableRedistributableFirmware = true;

  system.stateVersion = "25.11";
}
