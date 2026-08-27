{
  inputs,
  ...
}:
{
  imports = [
    # The vicinae home-manager module provides the `programs.vicinae`
    # options used by `./home/vicinae.nix`.
    inputs.vicinae.homeManagerModules.default

    ./home/wayle.nix
    ./home/vicinae.nix
    ./home/swayidle.nix
  ];

  services.wl-clip-persist.enable = true;
}
